package com.veyra.booking;

import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Size;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * The real missing piece behind the mobile apps' read-only rating
 * display: ride_ratings has existed in the schema since V002 (correctly
 * designed, with a UNIQUE(booking_id, rater_id) constraint already
 * preventing double-rating at the database level), but nothing ever
 * wrote to it -- both apps could only ever show a rating, never let
 * anyone actually give one.
 */
@RestController
@RequestMapping("/api/v1/bookings/{bookingId}/ratings")
public class RatingController {
  private final JdbcTemplate db;

  public RatingController(JdbcTemplate db) {
    this.db = db;
  }

  public record Rate(@Min(1) @Max(5) int score, @Size(max = 1000) String comment) {}

  @PostMapping
  public Map<String, Object> rate(@PathVariable UUID bookingId, @Valid @RequestBody Rate request) {
    UUID currentUserId = CurrentUser.id();

    List<Map<String, Object>> rows = db.queryForList(
        "select sb.creator_user_id,sb.status,d.user_id as driver_user_id " +
        "from scheduled_bookings sb left join drivers d on d.id=sb.selected_driver_id " +
        "where sb.id=?",
        bookingId);
    if (rows.isEmpty()) {
      throw new ApiException(HttpStatus.NOT_FOUND, "BOOKING_NOT_FOUND");
    }
    Map<String, Object> booking = rows.getFirst();

    if (!Set.of("COMPLETED", "CLOSED").contains((String) booking.get("status"))) {
      // Rating a trip that hasn't actually happened yet has no meaning --
      // and would let either party pre-emptively rate before the other's
      // side of the trip is even known.
      throw new ApiException(HttpStatus.CONFLICT, "BOOKING_NOT_COMPLETED");
    }

    UUID creatorId = (UUID) booking.get("creator_user_id");
    UUID driverUserId = (UUID) booking.get("driver_user_id");
    UUID ratedUserId;
    if (currentUserId.equals(creatorId)) {
      ratedUserId = driverUserId;
    } else if (currentUserId.equals(driverUserId)) {
      ratedUserId = creatorId;
    } else {
      throw new ApiException(HttpStatus.FORBIDDEN, "NOT_A_PARTICIPANT");
    }
    if (ratedUserId == null) {
      // No driver was ever matched on this booking (shouldn't reach
      // COMPLETED without one, but never silently rate a null user).
      throw new ApiException(HttpStatus.CONFLICT, "NO_COUNTERPARTY_TO_RATE");
    }

    UUID ratingId = UUID.randomUUID();
    try {
      db.update(
          "insert into ride_ratings(id,booking_id,rater_id,rated_user_id,score,comment) values (?,?,?,?,?,?)",
          ratingId, bookingId, currentUserId, ratedUserId, request.score(), request.comment());
    } catch (DuplicateKeyException e) {
      // The UNIQUE(booking_id, rater_id) constraint already guarantees
      // this at the database level -- caught here only to turn it into a
      // clean, expected API error rather than a raw SQL exception leaking
      // to the client.
      throw new ApiException(HttpStatus.CONFLICT, "ALREADY_RATED");
    }

    return Map.of("id", ratingId, "score", request.score());
  }

  @GetMapping
  public List<Map<String, Object>> list(@PathVariable UUID bookingId) {
    return db.queryForList(
        "select id,rater_id,rated_user_id,score,comment,created_at from ride_ratings where booking_id=?",
        bookingId);
  }
}
