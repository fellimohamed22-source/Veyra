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

  public NoShowController(
      JdbcTemplate db,
      CancellationFinanceService cancellationFinance){
    this.db=db;
    this.cancellationFinance=cancellationFinance;
  }

  @PostMapping("/{id}/no-show")
  @Transactional
  public Map<String,Object> noShow(@PathVariable UUID id){
    UUID driverId=db.queryForObject(
        "select id from drivers where user_id=?",
        UUID.class,CurrentUser.id());

    Map<String,Object> booking=db.queryForMap(
        "select selected_driver_id,status,scheduled_at from scheduled_bookings where id=? for update",
        id);

    if(!driverId.equals(booking.get("selected_driver_id")) ||
        !"DRIVER_ARRIVED".equals(booking.get("status"))){
      throw new ApiException(HttpStatus.FORBIDDEN,"NO_SHOW_NOT_ALLOWED");
    }

    if(OffsetDateTime.now().isBefore(
        DbTime.toOffsetDateTime(booking.get("scheduled_at")).plusMinutes(15))){
      throw new ApiException(HttpStatus.TOO_EARLY,"WAIT_PERIOD_NOT_FINISHED");
    }

    CancellationFinanceService.ChargeResult charge=
        cancellationFinance.noShow(id);

    db.update(
        "update scheduled_bookings set status='CUSTOMER_NO_SHOW',updated_at=now() where id=?",
        id);
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
