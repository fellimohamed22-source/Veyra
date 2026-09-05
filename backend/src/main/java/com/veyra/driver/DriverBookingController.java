package com.veyra.driver;

import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

import java.util.*;

@RestController
@RequestMapping("/api/v1/driver/bookings")
public class DriverBookingController {
  private final JdbcTemplate db;

  public DriverBookingController(JdbcTemplate db) {
    this.db = db;
  }

  @GetMapping
  public List<Map<String, Object>> mine(@RequestParam(defaultValue="upcoming") String scope) {
    UUID driverId = driverId();
    String states = "('CONFIRMED','DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_PROGRESS')";
    if ("history".equals(scope)) {
      states = "('COMPLETED','CLOSED','CANCELLED','DRIVER_CANCELLED','CUSTOMER_NO_SHOW')";
    }
    return db.queryForList(
        "select sb.id,sb.pickup_address,sb.dropoff_address,sb.scheduled_at,sb.status," +
        "sb.payment_method,sb.passenger_count,sb.baggage_count,bfs.driver_net_amount_minor,bfs.platform_commission_amount_minor,bfs.customer_total_amount_minor,bfs.currency " +
        "from scheduled_bookings sb left join booking_financial_snapshots bfs on bfs.booking_id=sb.id " +
        "where sb.selected_driver_id=? and sb.status in " + states + " order by sb.scheduled_at asc",
        driverId);
  }

  @GetMapping("/{bookingId}")
  public Map<String, Object> detail(@PathVariable UUID bookingId) {
    UUID driverId = driverId();
    List<Map<String, Object>> rows = db.queryForList(
        "select sb.id,sb.pickup_address,sb.dropoff_address,sb.scheduled_at,sb.status,sb.payment_method," +
        "coalesce(sb.beneficiary_name_snapshot,concat(cu.first_name,' ',coalesce(cu.last_name,''))) as customer_name," +
        "coalesce(sb.beneficiary_phone_snapshot,cu.phone) as customer_phone,sb.passenger_count,sb.baggage_count,sb.customer_notes," +
        "bfs.driver_net_amount_minor,bfs.platform_commission_amount_minor,bfs.customer_total_amount_minor,bfs.currency " +
        "from scheduled_bookings sb " +
        "join users cu on cu.id=sb.creator_user_id " +
        "left join booking_financial_snapshots bfs on bfs.booking_id=sb.id " +
        "where sb.id=? and sb.selected_driver_id=?",
        bookingId,
        driverId);
    if (rows.isEmpty()) {
      throw new ApiException(HttpStatus.NOT_FOUND, "BOOKING_NOT_FOUND");
    }
    return rows.getFirst();
  }

  private UUID driverId() {
    List<UUID> rows = db.queryForList(
        "select id from drivers where user_id=?",
        UUID.class,
        CurrentUser.id());
    if (rows.isEmpty()) {
      throw new ApiException(HttpStatus.FORBIDDEN, "DRIVER_PROFILE_REQUIRED");
    }
    return rows.getFirst();
  }
}
