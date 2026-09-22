package com.veyra.booking;

import com.veyra.finance.CancellationFinanceService;
import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import com.veyra.shared.DbTime;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.time.OffsetDateTime;
import java.util.*;

@RestController
@RequestMapping("/api/v1/bookings")
public class NoShowController {
  private final JdbcTemplate db;
  private final CancellationFinanceService cancellationFinance;
  private final BookingStatusHistoryService history;

  public NoShowController(
      JdbcTemplate db,
      CancellationFinanceService cancellationFinance,
      BookingStatusHistoryService history){
    this.db=db;
    this.cancellationFinance=cancellationFinance;
    this.history=history;
  }

  @PostMapping("/{id}/no-show")
  @Transactional
  public Map<String,Object> noShow(@PathVariable UUID id){
    UUID driverId=db.queryForObject(
        "select id from drivers where user_id=?",
        UUID.class,CurrentUser.id());

    Map<String,Object> booking=db.queryForMap(
        "select selected_driver_id,status,scheduled_at,(select max(created_at) from booking_status_history where booking_id=scheduled_bookings.id and to_status='DRIVER_ARRIVED') as arrived_at from scheduled_bookings where id=? for update",
        id);

    if(!driverId.equals(booking.get("selected_driver_id")) ||
        !"DRIVER_ARRIVED".equals(booking.get("status"))){
      throw new ApiException(HttpStatus.FORBIDDEN,"NO_SHOW_NOT_ALLOWED");
    }

    OffsetDateTime scheduled=DbTime.toOffsetDateTime(booking.get("scheduled_at"));
    OffsetDateTime arrived=DbTime.toOffsetDateTime(booking.get("arrived_at"));
    if(arrived==null)throw new ApiException(HttpStatus.CONFLICT,"ARRIVAL_TIME_UNAVAILABLE");
    OffsetDateTime waitFrom=arrived.isAfter(scheduled)?arrived:scheduled;
    if(OffsetDateTime.now().isBefore(waitFrom.plusMinutes(15))){
      throw new ApiException(HttpStatus.TOO_EARLY,"WAIT_PERIOD_NOT_FINISHED");
    }

    CancellationFinanceService.ChargeResult charge=
        cancellationFinance.noShow(id);

    db.update(
        "update scheduled_bookings set status='CUSTOMER_NO_SHOW',updated_at=now() where id=?",
        id);
    history.record(id,"DRIVER_ARRIVED","CUSTOMER_NO_SHOW","DRIVER",CurrentUser.id(),null);
    db.update(
        "insert into outbox_events(aggregate_type,aggregate_id,event_type,payload) " +
        "values ('BOOKING',?,'booking.status.customer_no_show',jsonb_build_object('bookingId',?::text))",
        id,id);

    Map<String,Object> result=new LinkedHashMap<>();
    result.put("status","CUSTOMER_NO_SHOW");
    result.put("noShowFeeMinor",charge.feeMinor());
    result.put("driverCompensationMinor",charge.driverCompensationMinor());
    result.put("platformAmountMinor",charge.platformAmountMinor());
    result.put("currency",charge.currency());
    result.put("refundQueued",charge.refundQueued());
    return result;
  }
}
