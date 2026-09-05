package com.veyra.booking;

import com.veyra.shared.ApiException;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * Real test coverage for the rating submission logic that closes a
 * genuine gap: ride_ratings existed in the schema since V002, correctly
 * designed (UNIQUE(booking_id, rater_id) preventing double-rating at the
 * database level), but nothing ever wrote to it before this controller.
 */
@ExtendWith(MockitoExtension.class)
class RatingControllerTest {

  @Mock JdbcTemplate db;

  private final UUID customerId = UUID.randomUUID();
  private final UUID driverUserId = UUID.randomUUID();
  private final UUID bookingId = UUID.randomUUID();

  private RatingController controller() {
    return new RatingController(db);
  }

  private void asUser(UUID userId) {
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(userId, null));
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  private void stubBooking(String status, UUID driverUserIdOrNull) {
    Map<String, Object> row = new HashMap<>();
    row.put("creator_user_id", customerId);
    row.put("status", status);
    row.put("driver_user_id", driverUserIdOrNull);
    when(db.queryForList(contains("from scheduled_bookings sb left join drivers"), eq(bookingId)))
        .thenReturn(List.of(row));
  }

  @Test
  void unknownBookingRejected() {
    asUser(customerId);
    when(db.queryForList(contains("from scheduled_bookings sb left join drivers"), eq(bookingId))).thenReturn(List.of());

    ApiException ex = assertThrows(ApiException.class, () -> controller().rate(bookingId, new RatingController.Rate(5, null)));

    assertEquals("BOOKING_NOT_FOUND", ex.code());
  }

  @Test
  void aTripStillInProgressCannotBeRatedYet() {
    asUser(customerId);
    stubBooking("IN_PROGRESS", driverUserId);

    ApiException ex = assertThrows(ApiException.class, () -> controller().rate(bookingId, new RatingController.Rate(5, null)));

    assertEquals("BOOKING_NOT_COMPLETED", ex.code());
    assertEquals(HttpStatus.CONFLICT, ex.status());
  }

  @Test
  void someoneNotInvolvedInTheBookingCannotRateIt() {
    asUser(UUID.randomUUID()); // neither the creator nor the driver
    stubBooking("COMPLETED", driverUserId);

    ApiException ex = assertThrows(ApiException.class, () -> controller().rate(bookingId, new RatingController.Rate(5, null)));

    assertEquals("NOT_A_PARTICIPANT", ex.code());
  }

  @Test
  void theCustomerRatesTheDriver() {
    asUser(customerId);
    stubBooking("COMPLETED", driverUserId);

    controller().rate(bookingId, new RatingController.Rate(5, "Great ride"));

    verify(db).update(contains("insert into ride_ratings"), any(), eq(bookingId), eq(customerId), eq(driverUserId), eq(5), eq("Great ride"));
  }

  @Test
  void theDriverRatesTheCustomer() {
    // Same booking, opposite direction -- the rated party flips based on
    // who the caller actually is, not a fixed "customer always rates
    // driver" assumption.
    asUser(driverUserId);
    stubBooking("CLOSED", driverUserId);

    controller().rate(bookingId, new RatingController.Rate(4, null));

    verify(db).update(contains("insert into ride_ratings"), any(), eq(bookingId), eq(driverUserId), eq(customerId), eq(4), isNull());
  }

  @Test
  void ratingTwiceForTheSameBookingIsRejectedCleanly() {
    asUser(customerId);
    stubBooking("COMPLETED", driverUserId);
    when(db.update(contains("insert into ride_ratings"), any(), any(), any(), any(), any(), any()))
        .thenThrow(new DuplicateKeyException("duplicate"));

    ApiException ex = assertThrows(ApiException.class, () -> controller().rate(bookingId, new RatingController.Rate(3, null)));

    // The database's own UNIQUE(booking_id, rater_id) constraint fires --
    // this must surface as a clean API error, not a raw SQL exception.
    assertEquals("ALREADY_RATED", ex.code());
  }

  @Test
  void aBookingWithNoMatchedDriverCannotBeRatedByAnyone() {
    asUser(customerId);
    stubBooking("COMPLETED", null);

    ApiException ex = assertThrows(ApiException.class, () -> controller().rate(bookingId, new RatingController.Rate(5, null)));

    assertEquals("NO_COUNTERPARTY_TO_RATE", ex.code());
  }

  @Test
  void listingRatingsReturnsThemForTheBooking() {
    when(db.queryForList(contains("from ride_ratings where booking_id=?"), eq(bookingId)))
        .thenReturn(List.of(Map.of("score", 5)));

    List<Map<String, Object>> ratings = controller().list(bookingId);

    assertEquals(1, ratings.size());
  }
}
