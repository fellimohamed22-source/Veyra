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
  private final LedgerService ledger;

  public FinanceOpsController(JdbcTemplate db, LedgerService ledger){
    this.db=db;
    this.ledger=ledger;
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
        "select amount_minor,paid_amount_minor,currency from driver_platform_debts where id=? for update",
        id);
    long total=((Number)debt.get("amount_minor")).longValue();
    long paid=((Number)debt.get("paid_amount_minor")).longValue();
    long next=Math.min(total,Math.addExact(paid,amountMinor));
    long actuallyApplied=next-paid;
    String status=next>=total?"PAID":"PARTIALLY_PAID";

    db.update(
        "update driver_platform_debts set paid_amount_minor=?,status=? where id=?",
        next,status,id);
    audit("DRIVER_CASH_DEBT_SETTLED","DRIVER_PLATFORM_DEBT",id);

    if(actuallyApplied>0){
      ledger.post("DRIVER_CASH_DEBT_SETTLED",null,"Driver remitted cash commission owed",(String)debt.get("currency"),List.of(
          LedgerService.Entry.debit("CASH_ON_HAND",actuallyApplied),
          LedgerService.Entry.credit("DRIVER_PLATFORM_DEBT",actuallyApplied)));
    }

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
      // Booked once, at the exact moment this debt reaches PAID -- matches
      // the timing of the driver_payable row above exactly (created here,
      // not progressively on each partial payment). The full fee amount
      // splits cleanly into platform's share + driver's compensation share
      // (CancellationFinanceService computes platform = fee - driverComp),
      // so the transaction balances against the full amount collected in
      // cash, not just this final increment.
      long platformShare=((Number)debt.get("amount_minor")).longValue()-compensation;
      List<LedgerService.Entry> entries=new ArrayList<>();
      entries.add(LedgerService.Entry.debit("CASH_ON_HAND",((Number)debt.get("amount_minor")).longValue()));
      if(platformShare>0) entries.add(LedgerService.Entry.credit("PLATFORM_REVENUE",platformShare));
      if(compensation>0) entries.add(LedgerService.Entry.credit("DRIVER_PAYABLE",compensation));
      ledger.post("CUSTOMER_CASH_DEBT_PAID",(UUID)debt.get("booking_id"),"Cancellation fee collected in cash, split between platform revenue and driver compensation",(String)debt.get("currency"),entries);
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
    List<Map<String,Object>> rows=db.queryForList(
        "select amount_minor,currency from driver_payables where id=? and status='PAYABLE' for update",
        id);
    if(rows.isEmpty()) throw new ApiException(HttpStatus.CONFLICT,"PAYABLE_NOT_AVAILABLE");
    Map<String,Object> payable=rows.getFirst();

    db.update("update driver_payables set status='PAID' where id=?",id);
    audit("DRIVER_PAYABLE_PAID","DRIVER_PAYABLE",id);

    ledger.post("DRIVER_PAYABLE_PAID",null,"Driver payable paid out",(String)payable.get("currency"),List.of(
        LedgerService.Entry.debit("DRIVER_PAYABLE",((Number)payable.get("amount_minor")).longValue()),
        LedgerService.Entry.credit("CASH_ON_HAND",((Number)payable.get("amount_minor")).longValue())));
  }

  private void audit(String action,String entityType,UUID entityId){
    db.update(
        "insert into audit_logs(actor_id,actor_type,action,entity_type,entity_id) " +
        "values (?,'FINANCE',?,?,?)",
        CurrentUser.id(),action,entityType,entityId);
  }
}
