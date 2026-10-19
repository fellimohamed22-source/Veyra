package com.veyra.admin;

import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.util.*;

/**
 * VEYRA review of VTC companies and their fleet (SOC-03/04): the company
 * validates its drivers, but only VEYRA opens the marketplace to the
 * company, to each vehicle and to each driver.
 */
@RestController
@RequestMapping("/api/v1/admin/companies")
@PreAuthorize("hasRole('ADMIN')")
public class AdminCompanyController {
  static final Set<String> REASONS = Set.of("DOCUMENT_INVALID", "DOCUMENT_EXPIRED", "DOCUMENT_MISSING", "IDENTITY_MISMATCH", "VEHICLE_NOT_COMPLIANT");

  private final JdbcTemplate db;

  public AdminCompanyController(JdbcTemplate db) { this.db = db; }

  public record Reason(String reasonCode) {}

  @GetMapping
  public List<Map<String, Object>> list() {
    return db.queryForList(
        "select c.id,c.legal_name,c.siren,c.revtc_number,c.status,c.created_at," +
        "(select count(*) from vehicles v where v.company_id=c.id) as vehicles," +
        "(select count(*) from vehicles v where v.company_id=c.id and v.status='PENDING') as pending_vehicles," +
        "(select count(*) from company_affiliations a where a.company_id=c.id and a.status='ACTIVE') as drivers " +
        "from vtc_companies c order by case c.status when 'SUBMITTED' then 0 else 1 end,c.created_at desc limit 500");
  }

  @GetMapping("/{id}")
  public Map<String, Object> detail(@PathVariable UUID id) {
    List<Map<String, Object>> c = db.queryForList(
        "select c.id,c.legal_name,c.siren,c.revtc_number,c.address,c.contact_email,c.status,c.rejection_reason_code,c.created_at,u.email::text as owner_email " +
        "from vtc_companies c join users u on u.id=c.created_by where c.id=?", id);
    if (c.isEmpty()) throw new ApiException(HttpStatus.NOT_FOUND, "COMPANY_NOT_FOUND");
    Map<String, Object> out = new LinkedHashMap<>(c.getFirst());
    out.put("documents", db.queryForList(
        "select id,type,status,vehicle_id,expires_at,original_filename,created_at from company_documents where company_id=? and status<>'SUPERSEDED' order by vehicle_id nulls first,type", id));
    out.put("vehicles", db.queryForList(
        "select v.id,v.brand,v.model,v.year,v.plate_number,v.seats,v.baggage_capacity,v.status,vc.display_name as category_name " +
        "from vehicles v join vehicle_categories vc on vc.id=v.category_id where v.company_id=? order by v.plate_number", id));
    return out;
  }

  /** Approves the company and its documents; vehicles are approved one by one. */
  @PostMapping("/{id}/approve")
  @Transactional
  public void approve(@PathVariable UUID id) {
    if (db.update("update vtc_companies set status='APPROVED',rejection_reason_code=null,updated_at=now() where id=? and status in ('SUBMITTED','SUSPENDED','REJECTED')", id) == 0)
      throw new ApiException(HttpStatus.CONFLICT, "COMPANY_NOT_REVIEWABLE");
    db.update("update company_documents set status='APPROVED' where company_id=? and vehicle_id is null and status='SUBMITTED'", id);
    audit("COMPANY_APPROVED", "COMPANY", id);
  }

  @PostMapping("/{id}/reject")
  public void reject(@PathVariable UUID id, @RequestBody Reason r) {
    String reason = reason(r);
    if (db.update("update vtc_companies set status='REJECTED',rejection_reason_code=?,updated_at=now() where id=? and status='SUBMITTED'", reason, id) == 0)
      throw new ApiException(HttpStatus.CONFLICT, "COMPANY_NOT_REVIEWABLE");
    audit("COMPANY_REJECTED", "COMPANY", id);
  }

  /** Suspension removes every fleet vehicle from the marketplace (FleetRules). */
  @PostMapping("/{id}/suspend")
  public void suspend(@PathVariable UUID id) {
    if (db.update("update vtc_companies set status='SUSPENDED',updated_at=now() where id=? and status='APPROVED'", id) == 0)
      throw new ApiException(HttpStatus.CONFLICT, "COMPANY_NOT_APPROVED");
    audit("COMPANY_SUSPENDED", "COMPANY", id);
  }

  @PostMapping("/{id}/vehicles/{vehicleId}/approve")
  @Transactional
  public void approveVehicle(@PathVariable UUID id, @PathVariable UUID vehicleId) {
    if (db.update("update vehicles set status='APPROVED' where id=? and company_id=? and status in ('PENDING','REJECTED')", vehicleId, id) == 0)
      throw new ApiException(HttpStatus.NOT_FOUND, "VEHICLE_NOT_FOUND");
    db.update("update company_documents set status='APPROVED' where vehicle_id=? and status='SUBMITTED'", vehicleId);
    audit("COMPANY_VEHICLE_APPROVED", "VEHICLE", vehicleId);
  }

  @PostMapping("/{id}/vehicles/{vehicleId}/reject")
  public void rejectVehicle(@PathVariable UUID id, @PathVariable UUID vehicleId, @RequestBody Reason r) {
    reason(r);
    if (db.update("update vehicles set status='REJECTED' where id=? and company_id=? and status in ('PENDING','APPROVED')", vehicleId, id) == 0)
      throw new ApiException(HttpStatus.NOT_FOUND, "VEHICLE_NOT_FOUND");
    audit("COMPANY_VEHICLE_REJECTED", "VEHICLE", vehicleId);
  }

  private static String reason(Reason r) {
    if (r == null || r.reasonCode() == null || !REASONS.contains(r.reasonCode())) throw new ApiException(HttpStatus.BAD_REQUEST, "REASON_CODE_INVALID");
    return r.reasonCode();
  }

  private void audit(String action, String entityType, UUID entityId) {
    db.update("insert into audit_logs(actor_id,actor_type,action,entity_type,entity_id) values (?,'ADMIN',?,?,?)", CurrentUser.id(), action, entityType, entityId);
  }
}
