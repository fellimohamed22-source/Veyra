package com.veyra.driver;

import com.veyra.booking.BookingController;
import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

import java.util.*;

/**
 * Driver home (DR-01, boards 02/12/13 P1): the « Disponible » switch and
 * the three counters (available requests, pending offers, upcoming
 * rides) with the next ride.
 */
@RestController
@RequestMapping("/api/v1/driver")
public class DriverDashboardController {
  /** Rides the driver is committed to and that are not over yet. */
  static final String UPCOMING_STATES = "('PENDING_PAYMENT','CONFIRMED','DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_PROGRESS')";

  private final JdbcTemplate db;
  public DriverDashboardController(JdbcTemplate db) { this.db = db; }

  public record Availability(Boolean acceptingRequests) {}

  @GetMapping("/availability")
  public Map<String, Object> availability() {
    return Map.of("acceptingRequests", accepting(driverId()));
  }

  @PutMapping("/availability")
  public Map<String, Object> setAvailability(@RequestBody Availability a) {
    if (a == null || a.acceptingRequests() == null) throw new ApiException(HttpStatus.BAD_REQUEST, "AVAILABILITY_REQUIRED");
    UUID d = driverId();
    db.update("update drivers set accepting_requests=? where id=?", a.acceptingRequests(), d);
    return Map.of("acceptingRequests", a.acceptingRequests());
  }

  @GetMapping("/dashboard")
  public Map<String, Object> dashboard() {
    UUID d = driverId();
    Map<String, Object> result = new LinkedHashMap<>();
    result.put("acceptingRequests", accepting(d));
    result.put("availableRequests", count(
        "select count(*) from scheduled_bookings sb where sb.status in ('OPEN_FOR_OFFERS','OFFERS_RECEIVED') and sb.offer_window_ends_at>now() and "
            + BookingController.ELIGIBLE_VEHICLE_SQL, d));
    result.put("pendingOffers", count(
        "select count(*) from driver_offers where driver_id=? and status='ACTIVE' and expires_at>now()", d));
    result.put("upcomingRides", count(
        "select count(*) from scheduled_bookings where selected_driver_id=? and status in " + UPCOMING_STATES, d));
    List<Map<String, Object>> next = db.queryForList(
        "select sb.id,sb.status,sb.scheduled_at,sb.pickup_address,sb.dropoff_address,sb.passenger_count,sb.baggage_count,vc.display_name as category_name "
            + "from scheduled_bookings sb join vehicle_categories vc on vc.id=sb.category_id "
            + "where sb.selected_driver_id=? and sb.status in " + UPCOMING_STATES + " order by sb.scheduled_at asc limit 1", d);
    result.put("nextRide", next.isEmpty() ? null : next.getFirst());
    return result;
  }

  boolean accepting(UUID d) {
    Boolean b = db.queryForObject("select accepting_requests from drivers where id=?", Boolean.class, d);
    return b == null || b;
  }

  private long count(String sql, UUID d) {
    Long n = db.queryForObject(sql, Long.class, d);
    return n == null ? 0 : n;
  }

  private UUID driverId() {
    List<UUID> ids = db.queryForList("select id from drivers where user_id=?", UUID.class, CurrentUser.id());
    if (ids.isEmpty()) throw new ApiException(HttpStatus.FORBIDDEN, "DRIVER_PROFILE_REQUIRED");
    return ids.getFirst();
  }
}
