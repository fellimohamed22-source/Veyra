package com.veyra.booking;

import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

import java.util.*;

@RestController
@RequestMapping("/api/v1/scheduled-bookings")
public class BookingOwnerController {
  private final JdbcTemplate db;

  public BookingOwnerController(JdbcTemplate db) {
    this.db = db;
  }

  @GetMapping("/{bookingId}")
  public Map<String, Object> detail(@PathVariable UUID bookingId) {
    List<Map<String, Object>> rows = db.queryForList(
        "select sb.id,sb.creator_user_id,sb.partner_id,sb.pickup_address,sb.dropoff_address," +
        "sb.scheduled_at,sb.status,sb.payment_method,sb.selected_driver_id," +
        "bfs.driver_net_amount_minor,bfs.platform_commission_amount_minor,bfs.customer_total_amount_minor,bfs.currency " +
        "from scheduled_bookings sb left join booking_financial_snapshots bfs on bfs.booking_id=sb.id where sb.id=?",
        bookingId);
    if (rows.isEmpty()) {
      throw new ApiException(HttpStatus.NOT_FOUND, "BOOKING_NOT_FOUND");
    }
    Map<String, Object> booking = rows.getFirst();
    authorize(booking);
    return booking;
  }

  private void authorize(Map<String, Object> booking) {
    UUID userId = CurrentUser.id();
    if (userId.equals(booking.get("creator_user_id"))) {
      return;
    }
    UUID partnerId = (UUID) booking.get("partner_id");
    if (partnerId != null) {
      Integer member = db.queryForObject(
          "select count(*) from partner_users where partner_id=? and user_id=? and status='ACTIVE'",
          Integer.class,
          partnerId,
          userId);
      if (member != null && member > 0) {
        return;
      }
    }
    throw new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN");
  }
}
