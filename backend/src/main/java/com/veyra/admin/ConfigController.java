package com.veyra.admin;

import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.util.*;

@RestController
@RequestMapping("/api/v1/admin/config")
@PreAuthorize("hasRole('ADMIN')")
public class ConfigController {
  private final JdbcTemplate db;

  public ConfigController(JdbcTemplate db){
    this.db=db;
  }

  public record Commission(int bps){}

  public record OfferVisibility(String mode){}

  @GetMapping("/offer-visibility")
  public Map<String,Object> currentOfferVisibility(){
    List<Map<String,Object>> rows=db.queryForList(
        "select mode,version_no from offer_visibility_policy_versions where status='ACTIVE' order by version_no desc limit 1");
    if(rows.isEmpty()) throw new ApiException(HttpStatus.NOT_FOUND,"OFFER_VISIBILITY_POLICY_MISSING");
    return rows.getFirst();
  }

  @PostMapping("/offer-visibility")
  @Transactional
  public void updateOfferVisibility(@RequestBody OfferVisibility body){
    if(!"PRIVATE".equals(body.mode())&&!"BEST_VISIBLE".equals(body.mode())){
      throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"INVALID_OFFER_VISIBILITY_MODE");
    }
    Integer version=db.queryForObject(
        "select coalesce(max(version_no),0)+1 from offer_visibility_policy_versions",
        Integer.class);
    db.update(
        "update offer_visibility_policy_versions set status='INACTIVE',effective_to=now() where status='ACTIVE'");
    db.update(
        "insert into offer_visibility_policy_versions(id,mode,version_no,status,effective_from) values (gen_random_uuid(),?,?,'ACTIVE',now())",
        body.mode(),version);
    audit("OFFER_VISIBILITY_MODE_UPDATED",null);
  }

  public record CancellationPolicy(
      int freeUntilMinutes,
      int midWindowFromMinutes,
      int midFeeBps,
      int lateFeeBps,
      int noShowFeeBps,
      int driverShareMidBps,
      int driverShareLateBps,
      int driverShareNoShowBps,
      long midFeeMinMinor,
      long noShowCapMinor){}

  @PostMapping("/commission/standard")
  @Transactional
  public void standard(@RequestBody Commission commission){
    validateBps(commission.bps(),"INVALID_COMMISSION");
    Integer version=db.queryForObject(
        "select coalesce(max(version_no),0)+1 from commission_policy_versions where scope_type='STANDARD'",
        Integer.class);
    db.update(
        "update commission_policy_versions set status='INACTIVE',effective_to=now() " +
        "where scope_type='STANDARD' and status='ACTIVE'");
    db.update(
        "insert into commission_policy_versions(id,scope_type,commission_bps,version_no,status,effective_from) " +
        "values (gen_random_uuid(),'STANDARD',?,?,'ACTIVE',now())",
        commission.bps(),version);
    audit("STANDARD_COMMISSION_UPDATED",null);
  }

  @PostMapping("/commission/partner/{partnerId}")
  @Transactional
  public void partner(
      @PathVariable UUID partnerId,
      @RequestBody Commission commission){
    validateBps(commission.bps(),"INVALID_COMMISSION");
    Integer version=db.queryForObject(
        "select coalesce(max(version_no),0)+1 from commission_policy_versions " +
        "where scope_type='PARTNER' and partner_id=?",
        Integer.class,partnerId);
    db.update(
        "update commission_policy_versions set status='INACTIVE',effective_to=now() " +
        "where scope_type='PARTNER' and partner_id=? and status='ACTIVE'",
        partnerId);
    db.update(
        "insert into commission_policy_versions(id,scope_type,partner_id,commission_bps,version_no,status,effective_from) " +
        "values (gen_random_uuid(),'PARTNER',?,?,?,'ACTIVE',now())",
        partnerId,commission.bps(),version);
    audit("PARTNER_COMMISSION_UPDATED",partnerId);
  }

  @GetMapping("/cancellation-policy")
  public Map<String,Object> cancellationPolicy(){
    List<Map<String,Object>> rows=db.queryForList(
        "select * from cancellation_policy_versions where status='ACTIVE' " +
        "order by version_no desc limit 1");
    if(rows.isEmpty()) throw new ApiException(HttpStatus.NOT_FOUND,"CANCELLATION_POLICY_MISSING");
    return rows.getFirst();
  }

  @PostMapping("/cancellation-policy")
  @Transactional
  public Map<String,Object> updateCancellationPolicy(
      @RequestBody CancellationPolicy policy){
    if(policy.freeUntilMinutes()<policy.midWindowFromMinutes() ||
        policy.midWindowFromMinutes()<0 ||
        policy.midFeeMinMinor()<0 ||
        policy.noShowCapMinor()<=0){
      throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"INVALID_CANCELLATION_POLICY");
    }
    validateBps(policy.midFeeBps(),"INVALID_CANCELLATION_POLICY");
    validateBps(policy.lateFeeBps(),"INVALID_CANCELLATION_POLICY");
    validateBps(policy.noShowFeeBps(),"INVALID_CANCELLATION_POLICY");
    validateBps(policy.driverShareMidBps(),"INVALID_CANCELLATION_POLICY");
    validateBps(policy.driverShareLateBps(),"INVALID_CANCELLATION_POLICY");
    validateBps(policy.driverShareNoShowBps(),"INVALID_CANCELLATION_POLICY");

    Integer version=db.queryForObject(
        "select coalesce(max(version_no),0)+1 from cancellation_policy_versions where scope_type='STANDARD'",
        Integer.class);

    db.update(
        "update cancellation_policy_versions set status='INACTIVE' " +
        "where scope_type='STANDARD' and status='ACTIVE'");

    UUID id=UUID.randomUUID();
    db.update(
        "insert into cancellation_policy_versions(" +
        "id,scope_type,version_no,free_until_minutes,mid_window_from_minutes," +
        "mid_fee_bps,late_fee_bps,no_show_fee_bps,driver_share_mid_bps," +
        "driver_share_late_bps,driver_share_no_show_bps,mid_fee_min_minor,no_show_cap_minor," +
        "status,effective_from) values (?,?,?,?,?,?,?,?,?,?,?,?,?,'ACTIVE',now())",
        id,"STANDARD",version,policy.freeUntilMinutes(),policy.midWindowFromMinutes(),
        policy.midFeeBps(),policy.lateFeeBps(),policy.noShowFeeBps(),
        policy.driverShareMidBps(),policy.driverShareLateBps(),policy.driverShareNoShowBps(),
        policy.midFeeMinMinor(),policy.noShowCapMinor());

    audit("CANCELLATION_POLICY_UPDATED",id);
    return Map.of("id",id,"version",version,"status","ACTIVE");
  }

  private void validateBps(int bps,String code){
    if(bps<0||bps>10000){
      throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,code);
    }
  }

  private void audit(String action,UUID entityId){
    db.update(
        "insert into audit_logs(actor_id,actor_type,action,entity_type,entity_id) " +
        "values (?,'ADMIN',?,'CONFIG',?)",
        CurrentUser.id(),action,entityId);
  }
}
