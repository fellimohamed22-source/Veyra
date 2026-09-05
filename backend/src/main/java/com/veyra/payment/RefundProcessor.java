package com.veyra.payment;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.util.*;

@Component
public class RefundProcessor {
  private final JdbcTemplate db;
  private final StripePaymentService stripe;

  public RefundProcessor(JdbcTemplate db,StripePaymentService stripe){
    this.db=db;
    this.stripe=stripe;
  }

  @Scheduled(fixedDelayString="${veyra.refunds.poll-ms:5000}")
  @Transactional
  public void process(){
    if(!stripe.isConfigured()) return;

    List<Map<String,Object>> rows=db.queryForList(
        "select r.id,r.amount_minor,r.idempotency_key,r.attempt_count,p.provider_payment_id " +
        "from refunds r join payments p on p.id=r.payment_id " +
        "where r.status='REQUESTED' and r.provider='STRIPE' " +
        "and (r.next_attempt_at is null or r.next_attempt_at<=now()) " +
        "order by r.created_at asc limit 20 for update skip locked");

    for(Map<String,Object> row:rows){
      UUID refundId=(UUID)row.get("id");
      String paymentIntentId=(String)row.get("provider_payment_id");
      long amount=((Number)row.get("amount_minor")).longValue();
      String idempotencyKey=(String)row.get("idempotency_key");
      int attempts=((Number)row.get("attempt_count")).intValue()+1;
      try{
        var refund=stripe.refund(paymentIntentId,amount,idempotencyKey);
        db.update(
            "update refunds set status='SUCCEEDED',provider_ref=?,failure_message=null," +
            "attempt_count=?,next_attempt_at=null,updated_at=now() where id=?",
            refund.getId(),attempts,refundId);
        db.update(
            "update payments p set status=case " +
            "when (select coalesce(sum(r.amount_minor),0) from refunds r where r.payment_id=p.id and r.status='SUCCEEDED')>=p.amount_minor " +
            "then 'REFUNDED' else 'PARTIALLY_REFUNDED' end " +
            "where p.id=(select payment_id from refunds where id=?)",
            refundId);
      }catch(Exception e){
        String message=e.getMessage();
        if(message==null||message.isBlank()) message=e.getClass().getSimpleName();
        if(message.length()>450) message=message.substring(0,450);
        if(attempts>=8){
          db.update(
              "update refunds set status='FAILED',attempt_count=?,failure_message=?,updated_at=now() where id=?",
              attempts,message,refundId);
        }else{
          long delaySeconds=Math.min(1800L,30L*(1L<<Math.min(attempts-1,6)));
          db.update(
              "update refunds set attempt_count=?,failure_message=?," +
              "next_attempt_at=now()+(? * interval '1 second'),updated_at=now() where id=?",
              attempts,message,delaySeconds,refundId);
        }
      }
    }
  }
}
