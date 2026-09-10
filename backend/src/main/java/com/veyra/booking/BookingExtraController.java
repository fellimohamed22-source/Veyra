package com.veyra.booking;

import com.veyra.finance.CancellationFinanceService;
import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import com.veyra.shared.DbTime;
import org.springframework.http.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.time.*;
import java.util.*;

@RestController
@RequestMapping("/api/v1/bookings")
public class BookingExtraController {
  private final JdbcTemplate db;
  private final CancellationFinanceService cancellationFinance;
  private final BookingStatusHistoryService history;

  public BookingExtraController(
      JdbcTemplate db,
      CancellationFinanceService cancellationFinance,
      BookingStatusHistoryService history){
    this.db=db;
    this.cancellationFinance=cancellationFinance;
    this.history=history;
  }

  @GetMapping("/{id}/pin-status")
  public Map<String,Object> pin(@PathVariable UUID id){
    Map<String,Object> booking=one(
        "select creator_user_id,partner_id,scheduled_at,status,pin_hash from scheduled_bookings where id=?",
        id);
    owner(booking);
    boolean visible=OffsetDateTime.now()
        .isAfter(DbTime.toOffsetDateTime(booking.get("scheduled_at")).minusHours(1));
    return Map.of(
        "available",visible,
        "note",visible
            ?"PIN available through the authorized PIN endpoint"
            :"Available at H-1");
  }

  @PostMapping("/{id}/cancel")
  @Transactional
  public Map<String,Object> cancel(@PathVariable UUID id){
    Map<String,Object> booking=one(
        "select creator_user_id,partner_id,scheduled_at,status from scheduled_bookings where id=? for update",
        id);
    owner(booking);

    String status=(String)booking.get("status");
    if(Set.of(
        "IN_PROGRESS","COMPLETED","CLOSED","CANCELLED","CUSTOMER_NO_SHOW")
        .contains(status)){
      throw new ApiException(HttpStatus.CONFLICT,"CANNOT_CANCEL");
    }

    long minutes=Duration.between(
        OffsetDateTime.now(),
        DbTime.toOffsetDateTime(booking.get("scheduled_at"))).toMinutes();

    CancellationFinanceService.ChargeResult charge=
        cancellationFinance.cancellation(id,minutes);

    db.update(
        "update scheduled_bookings set status='CANCELLED',updated_at=now() where id=?",
        id);
    history.record(id,status,"CANCELLED",booking.get("partner_id")!=null?"PARTNER":"CLIENT",CurrentUser.id(),null);
    db.update(
        "insert into outbox_events(aggregate_type,aggregate_id,event_type,payload) " +
        "values ('BOOKING',?,'booking.status.cancelled',jsonb_build_object('bookingId',?::text))",
        id,id);

    Map<String,Object> result=new LinkedHashMap<>();
    result.put("status","CANCELLED");
    result.put("cancellationFeeMinor",charge.feeMinor());
    result.put("driverCompensationMinor",charge.driverCompensationMinor());
    result.put("platformAmountMinor",charge.platformAmountMinor());
    result.put("currency",charge.currency());
    result.put("refundQueued",charge.refundQueued());
    return result;
  }

  private void owner(Map<String,Object> booking){
    if(CurrentUser.id().equals(booking.get("creator_user_id"))) return;
    UUID partnerId=(UUID)booking.get("partner_id");
    if(partnerId!=null){
      Integer count=db.queryForObject(
          "select count(*) from partner_users where partner_id=? and user_id=? and status='ACTIVE'",
          Integer.class,partnerId,CurrentUser.id());
      if(count!=null&&count>0) return;
    }
    throw new ApiException(HttpStatus.FORBIDDEN,"FORBIDDEN");
  }

  private Map<String,Object> one(String sql,Object... args){
    List<Map<String,Object>> rows=db.queryForList(sql,args);
    if(rows.isEmpty()) throw new ApiException(HttpStatus.NOT_FOUND,"NOT_FOUND");
    return rows.getFirst();
  }
}
