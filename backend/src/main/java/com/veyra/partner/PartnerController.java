package com.veyra.partner;

import com.veyra.security.CurrentUser;
import org.springframework.http.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.util.*;

@RestController
@RequestMapping("/api/v1/partner")
public class PartnerController {
  private final JdbcTemplate db;

  public PartnerController(JdbcTemplate db){
    this.db=db;
  }

  public record Org(String name,String partnerType,String billingEmail){}
  public record Guest(String fullName,String phone,String email,String externalReference){}

  @PostMapping("/organizations")
  @Transactional
  public ResponseEntity<Map<String,UUID>> createOrganization(@RequestBody Org request){
    UUID partnerId=UUID.randomUUID();
    db.update(
      "insert into partner_organizations(id,name,partner_type,status,billing_email) values (?,?,?,'SUBMITTED',?)",
      partnerId,request.name(),request.partnerType(),request.billingEmail());

    db.update(
      "insert into partner_users(partner_id,user_id,partner_role) values (?,?,'PARTNER_OWNER')",
      partnerId,CurrentUser.id());

    db.update(
      "insert into user_roles(user_id,role_id) select ?,id from roles where code='PARTNER_OWNER' on conflict do nothing",
      CurrentUser.id());

    db.update(
      "insert into commission_policy_versions(id,scope_type,partner_id,commission_bps,version_no,status,effective_from) " +
      "values (gen_random_uuid(),'PARTNER',?,600,1,'ACTIVE',now())",
      partnerId);

    return ResponseEntity.status(HttpStatus.CREATED).body(Map.of("partnerId",partnerId));
  }

  @GetMapping("/organizations")
  public List<Map<String,Object>> organizations(){
    return db.queryForList(
      "select po.id,po.name,po.partner_type,po.status,po.billing_email,po.credit_status,po.credit_limit_minor,po.currency,pu.partner_role " +
      "from partner_organizations po join partner_users pu on pu.partner_id=po.id " +
      "where pu.user_id=? and pu.status='ACTIVE' order by po.created_at desc",
      CurrentUser.id());
  }

  @PostMapping("/{partnerId}/beneficiaries")
  public ResponseEntity<Map<String,UUID>> createBeneficiary(
      @PathVariable UUID partnerId,
      @RequestBody Guest request){
    member(partnerId);
    UUID id=UUID.randomUUID();
    db.update(
      "insert into partner_beneficiaries(id,partner_id,full_name,phone,email,external_reference) values (?,?,?,?,?,?)",
      id,partnerId,request.fullName(),request.phone(),request.email(),request.externalReference());
    return ResponseEntity.status(HttpStatus.CREATED).body(Map.of("beneficiaryId",id));
  }

  // Gap P0 #3 (GAPS_REQUIRED_CHANGES.md / screen P33): only the write
  // side existed. A partner member had no way to actually list the
  // beneficiaries they'd already created.
  @GetMapping("/{partnerId}/beneficiaries")
  public List<Map<String,Object>> beneficiaries(@PathVariable UUID partnerId){
    member(partnerId);
    return db.queryForList(
      "select id,full_name,phone,email,external_reference,created_at " +
      "from partner_beneficiaries where partner_id=? order by created_at desc",
      partnerId);
  }

  // Gap P0 #4 (GAPS_REQUIRED_CHANGES.md / screen P34): the only existing
  // invoice-listing endpoint (PartnerInvoiceController) is
  // @PreAuthorize("hasAnyRole('FINANCE','ADMIN')") -- correct for staff
  // pulling any partner's invoices, but that means a partner's own member
  // had no read access to their own invoices at all. Deliberately a
  // SEPARATE endpoint under /partner/ (not widening Finance's role
  // requirement) scoped by the same member() check as every other partner
  // endpoint here.
  @GetMapping("/{partnerId}/invoices")
  public List<Map<String,Object>> invoices(@PathVariable UUID partnerId){
    member(partnerId);
    return db.queryForList(
      "select pi.id,pi.period_start,pi.period_end,pi.total_minor,pi.currency,pi.status,pi.due_at,pi.created_at," +
      "(select count(*) from partner_invoice_items pii where pii.invoice_id=pi.id) as items_count " +
      "from partner_invoices pi where pi.partner_id=? order by pi.created_at desc",
      partnerId);
  }

  @GetMapping("/{partnerId}/finance")
  public Map<String,Object> finance(@PathVariable UUID partnerId){
    member(partnerId);
    return db.queryForMap(
      "select po.credit_status,po.credit_limit_minor," +
      "coalesce(pia.outstanding_minor,0) outstanding_minor," +
      "coalesce(pia.overdue_minor,0) overdue_minor," +
      "coalesce((select commission_bps from commission_policy_versions cp " +
      "where cp.partner_id=po.id and cp.scope_type='PARTNER' and cp.status='ACTIVE' " +
      "order by cp.version_no desc limit 1),600) commission_bps " +
      "from partner_organizations po left join partner_invoice_accounts pia on pia.partner_id=po.id where po.id=?",
      partnerId);
  }

  private void member(UUID partnerId){
    Integer count=db.queryForObject(
      "select count(*) from partner_users where partner_id=? and user_id=? and status='ACTIVE'",
      Integer.class,partnerId,CurrentUser.id());
    if(count==null||count==0){
      throw new org.springframework.security.access.AccessDeniedException("partner");
    }
  }
}
