package com.veyra.payment;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

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
  public void process(){
    if(!stripe.isConfigured()) return;

    List<Map<String,Object>> rows=db.queryForList(
        "select r.id,r.amount_minor,r.idempotency_key,p.provider_payment_id " +
        "from refunds r join payments p on p.id=r.payment_id " +
        "where r.status='REQUESTED' and r.provider='STRIPE' order by r.created_at asc limit 20");

    for(Map<String,Object> row:rows){
      UUID refundId=(UUID)row.get("id");
      String paymentIntentId=(String)row.get("provider_payment_id");
      long amount=((Number)row.get("amount_minor")).longValue();
      String idempotencyKey=(String)row.get("idempotency_key");
      try{
        var refund=stripe.refund(paymentIntentId,amount,idempotencyKey);
        db.update(
            "update refunds set status='SUCCEEDED',provider_ref=?,failure_message=null,updated_at=now() where id=?",
            refund.getId(),refundId);
        db.update(
            "update payments p set status=case " +
            "when (select coalesce(sum(r.amount_minor),0) from refunds r where r.payment_id=p.id and r.status='SUCCEEDED')>=p.amount_minor " +
            "then 'REFUNDED' else 'PARTIALLY_REFUNDED' end " +
            "where p.id=(select payment_id from refunds where id=?)",
            refundId);
      }catch(Exception e){
        String message=e.getMessage();
        if(message!=null && message.length()>450) message=message.substring(0,450);
        db.update(
            "update refunds set status='FAILED',failure_message=?,updated_at=now() where id=?",
            message,refundId);
      }
    }
  }
}
