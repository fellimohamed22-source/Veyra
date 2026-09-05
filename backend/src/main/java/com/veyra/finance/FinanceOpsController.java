package com.veyra.finance;

import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.util.*;

@RestController
@RequestMapping("/api/v1/finance")
@PreAuthorize("hasAnyRole('FINANCE','ADMIN')")
public class FinanceOpsController {
  private final JdbcTemplate db;

  public FinanceOpsController(JdbcTemplate db){
    this.db=db;
  }

  @GetMapping("/cash-debts")
  public List<Map<String,Object>> driverDebts(){
    return db.queryForList(
        "select dpd.id,dpd.driver_id,dpd.booking_id,dpd.amount_minor,dpd.paid_amount_minor,dpd.currency,dpd.status " +
        "from driver_platform_debts dpd order by dpd.created_at desc");
  }

  @PostMapping("/cash-debts/{id}/settle")
  @Transactional
  public Map<String,Object> settleDriverDebt(
      @PathVariable UUID id,
      @RequestParam long amountMinor){
    if(amountMinor<=0) throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"INVALID_SETTLEMENT_AMOUNT");

    Map<String,Object> debt=db.queryForMap(
        "select amount_minor,paid_amount_minor from driver_platform_debts where id=? for update",
        id);
    long total=((Number)debt.get("amount_minor")).longValue();
    long paid=((Number)debt.get("paid_amount_minor")).longValue();
    long next=Math.min(total,Math.addExact(paid,amountMinor));
    String status=next>=total?"PAID":"PARTIALLY_PAID";

    db.update(
        "update driver_platform_debts set paid_amount_minor=?,status=? where id=?",
        next,status,id);
    audit("DRIVER_CASH_DEBT_SETTLED","DRIVER_PLATFORM_DEBT",id);

    return Map.of("paidAmountMinor",next,"remainingMinor",Math.max(0,total-next),"status",status);
  }

  @GetMapping("/customer-debts")
  public List<Map<String,Object>> customerDebts(){
    return db.queryForList(
        "select cpd.id,cpd.user_id,cpd.driver_id,cpd.booking_id,cpd.amount_minor,cpd.paid_amount_minor," +
        "cpd.driver_compensation_minor,cpd.platform_amount_minor,cpd.currency,cpd.status,u.email " +
        "from customer_platform_debts cpd join users u on u.id=cpd.user_id " +
        "order by cpd.created_at desc");
  }

  @PostMapping("/customer-debts/{id}/settle")
  @Transactional
  public Map<String,Object> settleCustomerDebt(
      @PathVariable UUID id,
      @RequestParam long amountMinor){
    if(amountMinor<=0) throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"INVALID_SETTLEMENT_AMOUNT");

    Map<String,Object> debt=db.queryForMap(
        "select user_id,driver_id,booking_id,amount_minor,paid_amount_minor,driver_compensation_minor,currency,status " +
        "from customer_platform_debts where id=? for update",
        id);

    long total=((Number)debt.get("amount_minor")).longValue();
    long paid=((Number)debt.get("paid_amount_minor")).longValue();
    long next=Math.min(total,Math.addExact(paid,amountMinor));
    String status=next>=total?"PAID":"PARTIALLY_PAID";

    db.update(
        "update customer_platform_debts set paid_amount_minor=?,status=?,updated_at=now() where id=?",
        next,status,id);

    if("PAID".equals(status) && debt.get("driver_id")!=null){
      long compensation=((Number)debt.get("driver_compensation_minor")).longValue();
      if(compensation>0){
        db.update(
            "insert into driver_payables(driver_id,booking_id,amount_minor,currency,status) " +
            "values (?,?,?,?,'PAYABLE') " +
            "on conflict(booking_id) do update set amount_minor=excluded.amount_minor,status='PAYABLE'",
            debt.get("driver_id"),debt.get("booking_id"),compensation,debt.get("currency"));
      }
    }

    audit("CUSTOMER_CASH_DEBT_SETTLED","CUSTOMER_PLATFORM_DEBT",id);
    return Map.of("paidAmountMinor",next,"remainingMinor",Math.max(0,total-next),"status",status);
  }

  @GetMapping("/payables")
  public List<Map<String,Object>> payables(){
    return db.queryForList(
        "select id,driver_id,booking_id,amount_minor,currency,status,created_at " +
        "from driver_payables order by created_at desc");
  }

  @PostMapping("/payables/{id}/mark-paid")
  @Transactional
  public void markPayablePaid(@PathVariable UUID id){
    int updated=db.update(
        "update driver_payables set status='PAID' where id=? and status='PAYABLE'",
        id);
    if(updated==0) throw new ApiException(HttpStatus.CONFLICT,"PAYABLE_NOT_AVAILABLE");
    audit("DRIVER_PAYABLE_PAID","DRIVER_PAYABLE",id);
  }

  private void audit(String action,String entityType,UUID entityId){
    db.update(
        "insert into audit_logs(actor_id,actor_type,action,entity_type,entity_id) " +
        "values (?,'FINANCE',?,?,?)",
        CurrentUser.id(),action,entityType,entityId);
  }
}
