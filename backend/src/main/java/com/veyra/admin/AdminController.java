package com.veyra.admin;

import com.veyra.security.CurrentUser;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.util.*;

@RestController
@RequestMapping("/api/v1/admin")
@PreAuthorize("hasRole('ADMIN')")
public class AdminController {
  private final JdbcTemplate db;

  public AdminController(JdbcTemplate db){
    this.db=db;
  }

  @GetMapping("/dashboard")
  public Map<String,Object> dashboard(){
    return Map.of(
      "bookings",db.queryForObject("select count(*) from scheduled_bookings",Long.class),
      "pendingDrivers",db.queryForObject("select count(*) from drivers where kyc_status in ('SUBMITTED','UNDER_REVIEW')",Long.class),
      "pendingPartners",db.queryForObject("select count(*) from partner_organizations where status in ('SUBMITTED','UNDER_REVIEW')",Long.class)
    );
  }

  @GetMapping("/drivers")
  public List<Map<String,Object>> drivers(){
    return db.queryForList(
      "select d.id,u.first_name,u.last_name,u.email,u.phone,d.status,d.kyc_status,d.marketplace_enabled,d.rating " +
      "from drivers d join users u on u.id=d.user_id order by d.created_at desc limit 500");
  }

  @PostMapping("/drivers/{id}/approve")
  public void approveDriver(@PathVariable UUID id){
    db.update(
      "update drivers set kyc_status='APPROVED',status='ACTIVE',marketplace_enabled=true where id=?",
      id);
    db.update("update driver_documents set status='APPROVED' where driver_id=? and status='SUBMITTED'",id);
    db.update("update vehicles set status='APPROVED' where driver_id=? and status='PENDING'",id);
    audit("DRIVER_KYC_APPROVED","DRIVER",id);
  }

  public record RejectRequest(String reasonCode){}

  @PostMapping("/drivers/{id}/reject")
  public void rejectDriver(@PathVariable UUID id,@RequestBody RejectRequest request){
    db.update(
      "update drivers set kyc_status='REJECTED',status='PENDING_KYC',marketplace_enabled=false where id=?",
      id);
    db.update("update driver_documents set status='REJECTED',rejection_reason_code=? where driver_id=? and status='SUBMITTED'",request.reasonCode(),id);
    db.update(
      "insert into kyc_reviews(driver_id,reviewer_id,decision,reason_code) values (?,?,'REJECTED',?)",
      id,CurrentUser.id(),request.reasonCode());
    audit("DRIVER_KYC_REJECTED","DRIVER",id);
  }

  @GetMapping("/partners")
  public List<Map<String,Object>> partners(){
    return db.queryForList(
      "select id,name,partner_type,status,billing_email,credit_status,credit_limit_minor,currency,created_at " +
      "from partner_organizations order by created_at desc limit 500");
  }

  @PostMapping("/partners/{id}/approve")
  public void approvePartner(@PathVariable UUID id){
    db.update(
      "update partner_organizations set status='APPROVED',credit_status='APPROVED' where id=?",
      id);
    db.update(
      "insert into partner_invoice_accounts(partner_id) values (?) on conflict do nothing",
      id);
    db.update(
      "insert into commission_policy_versions(id,scope_type,partner_id,commission_bps,version_no,status,effective_from) " +
      "select gen_random_uuid(),'PARTNER',?,600,1,'ACTIVE',now() " +
      "where not exists(select 1 from commission_policy_versions where scope_type='PARTNER' and partner_id=?)",
      id,id);
    audit("PARTNER_APPROVED","PARTNER",id);
  }

  @PostMapping("/partners/{id}/suspend")
  public void suspendPartner(@PathVariable UUID id){
    db.update(
      "update partner_organizations set status='SUSPENDED',credit_status='ON_HOLD' where id=?",
      id);
    db.update(
      "update partner_invoice_accounts set status='ON_HOLD' where partner_id=?",
      id);
    audit("PARTNER_SUSPENDED","PARTNER",id);
  }

  @GetMapping("/bookings")
  public List<Map<String,Object>> bookings(){
    return db.queryForList(
      "select id,creator_type,scheduled_at,status,payment_method,selected_driver_id,pickup_address,dropoff_address " +
      "from scheduled_bookings order by created_at desc limit 500");
  }

  private void audit(String action,String entityType,UUID entityId){
    db.update(
      "insert into audit_logs(actor_id,actor_type,action,entity_type,entity_id) values (?,'ADMIN',?,?,?)",
      CurrentUser.id(),action,entityType,entityId);
  }
}
