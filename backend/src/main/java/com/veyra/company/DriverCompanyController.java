package com.veyra.company;

import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.util.*;

/**
 * Affiliated driver side (board 08 C, DR-AFF-01..07): join a company with
 * its invitation code, follow the request, see the assigned vehicle, leave.
 */
@RestController
@RequestMapping("/api/v1/driver/company")
public class DriverCompanyController {
  private final JdbcTemplate db;

  public DriverCompanyController(JdbcTemplate db) { this.db = db; }

  public record Join(String code) {}

  /** Current attachment (pending or active), or an empty object. */
  @GetMapping
  public Map<String, Object> current() {
    UUID d = driver();
    List<Map<String, Object>> rows = db.queryForList(
        "select a.id as affiliation_id,a.status,a.requested_at,a.decided_at,c.id as company_id,c.legal_name,c.status as company_status " +
        "from company_affiliations a join vtc_companies c on c.id=a.company_id where a.driver_id=? " +
        "order by case when a.status in ('PENDING','ACTIVE') then 0 else 1 end,coalesce(a.decided_at,a.requested_at) desc limit 1", d);
    if (rows.isEmpty()) return Map.of();
    Map<String, Object> out = new LinkedHashMap<>(rows.getFirst());
    out.put("vehicles", db.queryForList(
        "select v.id,v.brand,v.model,v.plate_number,v.status,vc.display_name as category_name from vehicles v join vehicle_categories vc on vc.id=v.category_id " +
        "where v.driver_id=? and v.company_id=?", d, out.get("company_id")));
    return out;
  }

  /** DR-AFF: request to join the company owning this invitation code. */
  @PostMapping("/join")
  @Transactional
  public ResponseEntity<Map<String, Object>> join(@RequestBody Join j) {
    UUID d = driver();
    String code = j == null || j.code() == null ? "" : j.code().trim().toUpperCase(Locale.ROOT).replaceAll("\\s", "");
    if (!code.matches("[A-Z0-9]{4}-?[A-Z0-9]{4}")) throw new ApiException(HttpStatus.BAD_REQUEST, "INVITE_CODE_INVALID");
    if (code.length() == 8) code = code.substring(0, 4) + "-" + code.substring(4);
    List<Map<String, Object>> c = db.queryForList(
        "select id,legal_name from vtc_companies where invite_code=? and status in ('DRAFT','SUBMITTED','APPROVED')", code);
    if (c.isEmpty()) throw new ApiException(HttpStatus.NOT_FOUND, "INVITE_CODE_INVALID");
    UUID company = (UUID) c.getFirst().get("id");
    UUID id = UUID.randomUUID();
    try {
      db.update("insert into company_affiliations(id,company_id,driver_id) values (?,?,?)", id, company, d);
    } catch (DuplicateKeyException e) {
      throw new ApiException(HttpStatus.CONFLICT, "AFFILIATION_EXISTS");
    }
    db.update("update drivers set driver_type='AFFILIATED' where id=?", d);
    db.update("update company_invitations ci set status='ACCEPTED' from users u, drivers dr " +
        "where dr.id=? and u.id=dr.user_id and lower(ci.email)=lower(u.email::text) and ci.company_id=? and ci.status='PENDING'", d, company);
    return ResponseEntity.status(HttpStatus.CREATED).body(Map.of("affiliationId", id, "companyName", c.getFirst().get("legal_name"), "status", "PENDING"));
  }

  /** Withdraws a pending request or leaves the company; its vehicles are returned. */
  @DeleteMapping
  @Transactional
  public Map<String, Object> leave() {
    UUID d = driver();
    List<Map<String, Object>> a = db.queryForList(
        "select id,company_id,status from company_affiliations where driver_id=? and status in ('PENDING','ACTIVE') for update", d);
    if (a.isEmpty()) throw new ApiException(HttpStatus.NOT_FOUND, "AFFILIATION_NOT_FOUND");
    db.update("update company_affiliations set status='ENDED',decided_at=now(),decided_by=? where id=?", CurrentUser.id(), a.getFirst().get("id"));
    db.update("update vehicles set driver_id=null where company_id=? and driver_id=?", a.getFirst().get("company_id"), d);
    return Map.of("status", "ENDED");
  }

  private UUID driver() {
    List<UUID> d = db.queryForList("select id from drivers where user_id=?", UUID.class, CurrentUser.id());
    if (d.isEmpty()) throw new ApiException(HttpStatus.NOT_FOUND, "DRIVER_NOT_FOUND");
    return d.getFirst();
  }
}
