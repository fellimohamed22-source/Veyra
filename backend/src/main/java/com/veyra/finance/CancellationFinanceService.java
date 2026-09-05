package com.veyra.finance;

import com.veyra.shared.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.*;

@Service
public class CancellationFinanceService {
  private final JdbcTemplate db;

  public CancellationFinanceService(JdbcTemplate db){
    this.db=db;
  }

  public record ChargeResult(
      long feeMinor,
      long driverCompensationMinor,
      long platformAmountMinor,
      String currency,
      boolean refundQueued){}

  @Transactional
  public ChargeResult cancellation(UUID bookingId,long minutesToDeparture){
    Map<String,Object> policy=activePolicy();
    int free=((Number)policy.get("free_until_minutes")).intValue();
    int midFrom=((Number)policy.get("mid_window_from_minutes")).intValue();

    if(minutesToDeparture>=free){
      return charge(bookingId,policy,0,0);
    }
    if(minutesToDeparture>=midFrom){
      return charge(
          bookingId,
          policy,
          ((Number)policy.get("mid_fee_bps")).intValue(),
          ((Number)policy.get("driver_share_mid_bps")).intValue());
    }
    return charge(
        bookingId,
        policy,
        ((Number)policy.get("late_fee_bps")).intValue(),
        ((Number)policy.get("driver_share_late_bps")).intValue());
  }

  @Transactional
  public ChargeResult noShow(UUID bookingId){
    Map<String,Object> policy=activePolicy();
    return charge(
        bookingId,
        policy,
        ((Number)policy.get("no_show_fee_bps")).intValue(),
        ((Number)policy.get("driver_share_no_show_bps")).intValue());
  }

  private Map<String,Object> activePolicy(){
    List<Map<String,Object>> rows=db.queryForList(
        "select * from cancellation_policy_versions where status='ACTIVE' " +
        "and (effective_from is null or effective_from<=now()) order by version_no desc limit 1");
    if(rows.isEmpty()){
      throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR,"CANCELLATION_POLICY_MISSING");
    }
    return rows.getFirst();
  }

  private ChargeResult charge(
      UUID bookingId,
      Map<String,Object> policy,
      int feeBps,
      int driverShareBps){

    List<Map<String,Object>> financialRows=db.queryForList(
        "select sb.payment_method,sb.selected_driver_id,bfs.driver_proposed_amount_minor," +
        "bfs.customer_total_amount_minor,bfs.currency " +
        "from scheduled_bookings sb left join booking_financial_snapshots bfs on bfs.booking_id=sb.id " +
        "where sb.id=?",
        bookingId);

    if(financialRows.isEmpty()){
      throw new ApiException(HttpStatus.NOT_FOUND,"BOOKING_NOT_FOUND");
    }

    Map<String,Object> financial=financialRows.getFirst();
    if(financial.get("driver_proposed_amount_minor")==null || financial.get("selected_driver_id")==null){
      return new ChargeResult(0,0,0,"EUR",false);
    }

    long base=((Number)financial.get("driver_proposed_amount_minor")).longValue();
    long fee=percentage(base,feeBps);
    long driverComp=percentage(fee,driverShareBps);
    long platform=Math.max(0,fee-driverComp);
    String currency=(String)financial.get("currency");

    if(fee>0){
      db.update(
          "insert into cancellation_charges(booking_id,policy_id,charged_amount_minor,driver_compensation_minor,platform_amount_minor,currency) " +
          "values (?,?,?,?,?,?)",
          bookingId,policy.get("id"),fee,driverComp,platform,currency);
    }

    String method=(String)financial.get("payment_method");
    UUID driverId=(UUID)financial.get("selected_driver_id");
    boolean refundQueued=false;

    if("ONLINE".equals(method)){
      List<Map<String,Object>> captured=db.queryForList(
          "select id,amount_minor,currency,provider,provider_payment_id " +
          "from payments where booking_id=? and status='CAPTURED' order by created_at desc limit 1",
          bookingId);
      if(!captured.isEmpty()){
        Map<String,Object> payment=captured.getFirst();
        long paid=((Number)payment.get("amount_minor")).longValue();
        long refund=Math.max(0,paid-fee);
        if(refund>0){
          db.update(
              "insert into refunds(payment_id,booking_id,amount_minor,currency,provider,status,idempotency_key) " +
              "values (?,?,?,?,?,'REQUESTED',?) on conflict(idempotency_key) do nothing",
              payment.get("id"),bookingId,refund,payment.get("currency"),payment.get("provider"),
              "cancel-refund-"+bookingId);
          refundQueued=true;
        }
        if(driverComp>0){
          upsertDriverPayable(driverId,bookingId,driverComp,currency);
        }
      }
    }else if("PARTNER_INVOICE".equals(method)){
      if(driverComp>0){
        upsertDriverPayable(driverId,bookingId,driverComp,currency);
      }
    }

    return new ChargeResult(fee,driverComp,platform,currency,refundQueued);
  }

  private void upsertDriverPayable(UUID driverId,UUID bookingId,long amount,String currency){
    db.update(
        "insert into driver_payables(driver_id,booking_id,amount_minor,currency,status) " +
        "values (?,?,?,?,'PAYABLE') " +
        "on conflict(booking_id) do update set amount_minor=excluded.amount_minor,currency=excluded.currency,status='PAYABLE'",
        driverId,bookingId,amount,currency);
  }

  private long percentage(long amount,int bps){
    return BigDecimal.valueOf(amount)
        .multiply(BigDecimal.valueOf(bps))
        .divide(BigDecimal.valueOf(10000),0,RoundingMode.HALF_UP)
        .longValueExact();
  }
}
