package com.veyra.driver;

import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import com.veyra.shared.DbTime;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.time.*;
import java.util.*;

@RestController
@RequestMapping("/api/v1/driver/bookings")
public class DriverCancellationController {
  private final JdbcTemplate db;

  public DriverCancellationController(JdbcTemplate db){
    this.db=db;
  }

  public record CancelRequest(String reasonCode){}

  @PostMapping("/{bookingId}/cancel")
  @Transactional
  public Map<String,Object> cancel(
      @PathVariable UUID bookingId,
      @RequestBody(required=false) CancelRequest request){

    UUID driverId=db.queryForObject(
        "select id from drivers where user_id=?",
        UUID.class,CurrentUser.id());

    List<Map<String,Object>> rows=db.queryForList(
        "select id,status,scheduled_at,payment_method,selected_driver_id " +
        "from scheduled_bookings where id=? for update",
        bookingId);
    if(rows.isEmpty()) throw new ApiException(HttpStatus.NOT_FOUND,"BOOKING_NOT_FOUND");

    Map<String,Object> booking=rows.getFirst();
    if(!driverId.equals(booking.get("selected_driver_id"))){
      throw new ApiException(HttpStatus.FORBIDDEN,"NOT_SELECTED_DRIVER");
    }

    String status=(String)booking.get("status");
    if(!Set.of("CONFIRMED","DRIVER_EN_ROUTE").contains(status)){
      throw new ApiException(HttpStatus.CONFLICT,"DRIVER_CANNOT_CANCEL_NOW");
    }

    OffsetDateTime scheduledAt=DbTime.toOffsetDateTime(booking.get("scheduled_at"));
    long minutes=Duration.between(OffsetDateTime.now(),scheduledAt).toMinutes();
    String reason=request==null||request.reasonCode()==null||request.reasonCode().isBlank()
        ?"DRIVER_CANCELLED"
        :request.reasonCode().trim();

    db.update(
        "insert into driver_quality_events(driver_id,booking_id,event_type,severity,metadata) " +
        "values (?,?,'BOOKING_CANCELLED',2,jsonb_build_object('reason',?))",
        driverId,bookingId,reason);

    queueFullOnlineRefund(bookingId);

    db.update("delete from booking_financial_snapshots where booking_id=?",bookingId);

    db.update(
        "update driver_offers set status='WITHDRAWN' where booking_id=? and status='ACCEPTED'",
        bookingId);

    boolean republished=minutes>15;
    if(republished){
      OffsetDateTime newClose=scheduledAt.minusMinutes(15);
      db.update(
          "update scheduled_bookings set status='OPEN_FOR_OFFERS',selected_offer_id=null," +
          "selected_driver_id=null,pin_hash=null,pin_encrypted=null,offer_window_ends_at=?,updated_at=now() where id=?",
          newClose,bookingId);

      db.update(
          "insert into outbox_events(aggregate_type,aggregate_id,event_type,payload) " +
          "values ('BOOKING',?,'booking.driver_cancelled',jsonb_build_object('bookingId',?::text))",
          bookingId,bookingId);
      db.update(
          "insert into outbox_events(aggregate_type,aggregate_id,event_type,payload) " +
          "values ('BOOKING',?,'booking.published',jsonb_build_object('bookingId',?::text,'priority',true))",
          bookingId,bookingId);
    }else{
      db.update(
          "update scheduled_bookings set status='DRIVER_CANCELLED',updated_at=now() where id=?",
          bookingId);
      db.update(
          "insert into outbox_events(aggregate_type,aggregate_id,event_type,payload) " +
          "values ('BOOKING',?,'booking.driver_cancelled',jsonb_build_object('bookingId',?::text,'urgent',true))",
          bookingId,bookingId);
    }

    return Map.of(
        "status",republished?"OPEN_FOR_OFFERS":"DRIVER_CANCELLED",
        "republished",republished,
        "minutesBeforeDeparture",minutes);
  }

  private void queueFullOnlineRefund(UUID bookingId){
    List<Map<String,Object>> payments=db.queryForList(
        "select id,amount_minor,currency,provider from payments " +
        "where booking_id=? and status='CAPTURED' order by created_at desc limit 1",
        bookingId);
    if(payments.isEmpty()) return;

    Map<String,Object> payment=payments.getFirst();
    db.update(
        "insert into refunds(payment_id,booking_id,amount_minor,currency,provider,status,idempotency_key) " +
        "values (?,?,?,?,?,'REQUESTED',?) on conflict(idempotency_key) do nothing",
        payment.get("id"),bookingId,payment.get("amount_minor"),payment.get("currency"),
        payment.get("provider"),"driver-cancel-refund-"+bookingId);
  }
}
