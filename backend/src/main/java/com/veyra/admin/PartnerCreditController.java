package com.veyra.admin;

import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.util.*;

@RestController
@RequestMapping("/api/v1/admin/partners")
@PreAuthorize("hasRole('ADMIN')")
public class PartnerCreditController {
  private final JdbcTemplate db;

  public PartnerCreditController(JdbcTemplate db){ this.db=db; }

  public record Credit(long creditLimitMinor,int paymentTermsDays,String billingCycle){}

  @PutMapping("/{id}/credit")
  public void credit(@PathVariable UUID id,@RequestBody Credit credit){
    if(credit.creditLimitMinor()<0 || credit.paymentTermsDays()<1 || credit.paymentTermsDays()>90 ||
        credit.billingCycle()==null || !Set.of("WEEKLY","MONTHLY").contains(credit.billingCycle())){
      throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"INVALID_PARTNER_CREDIT");
    }
    Integer exists=db.queryForObject(
        "select count(*) from partner_organizations where id=?",
        Integer.class,id);
    if(exists==null||exists==0){
      throw new ApiException(HttpStatus.NOT_FOUND,"PARTNER_NOT_FOUND");
    }
    db.update(
        "update partner_organizations set credit_limit_minor=?,credit_status='APPROVED' where id=?",
        credit.creditLimitMinor(),id);
    db.update(
        "insert into partner_invoice_accounts(partner_id,payment_terms_days,billing_cycle) values (?,?,?) " +
        "on conflict(partner_id) do update set payment_terms_days=excluded.payment_terms_days," +
        "billing_cycle=excluded.billing_cycle,status='ACTIVE'",
        id,credit.paymentTermsDays(),credit.billingCycle());
    db.update(
        "insert into audit_logs(actor_id,actor_type,action,entity_type,entity_id,metadata) " +
        "values (?,'ADMIN','PARTNER_CREDIT_UPDATED','PARTNER',?,jsonb_build_object(" +
        "'creditLimitMinor',?,'paymentTermsDays',?,'billingCycle',?))",
        CurrentUser.id(),id,credit.creditLimitMinor(),credit.paymentTermsDays(),credit.billingCycle());
  }
}
