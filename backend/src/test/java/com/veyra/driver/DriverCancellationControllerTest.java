package com.veyra.driver;

import com.veyra.shared.ApiException;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * The real, genuinely consequential decision this controller makes --
 * republish the booking for new offers versus terminate it outright,
 * based on how much time remains before the scheduled departure -- had
 * zero coverage before this. Getting the 15-minute boundary wrong either
 * direction is a real incident: republishing too close to departure gives
 * no realistic time for a new driver to be found, terminating too early
 * needlessly strands a customer who could have been rematched.
 */
@ExtendWith(MockitoExtension.class)
class DriverCancellationControllerTest {

  @Mock JdbcTemplate db;

  private final UUID userId = UUID.randomUUID();
  private final UUID driverId = UUID.randomUUID();
  private final UUID bookingId = UUID.randomUUID();

  @BeforeEach
  void setUpSecurityContext() {
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(userId, null));
    lenient().when(db.queryForObject(eq("select id from drivers where user_id=?"), eq(UUID.class), any(Object[].class)))
        .thenReturn(driverId);
    // No captured payment by default -- most scenarios here aren't about
    // the refund path specifically.
    lenient().when(db.queryForList(contains("from payments"), any(Object[].class))).thenReturn(List.of());
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  private DriverCancellationController controller() {
    return new DriverCancellationController(db);
  }

  private void stubBooking(UUID selectedDriverId, String status, OffsetDateTime scheduledAt) {
    when(db.queryForList(contains("from scheduled_bookings where id=? for update"), eq(bookingId)))
        .thenReturn(List.of(Map.of(
            "id", bookingId, "status", status, "scheduled_at", scheduledAt,
            "payment_method", "ONLINE", "selected_driver_id", selectedDriverId)));
  }

  @Test
  void unknownBookingRejected() {
    when(db.queryForList(contains("from scheduled_bookings where id=? for update"), eq(bookingId)))
        .thenReturn(List.of());

    ApiException ex = assertThrows(ApiException.class, () -> controller().cancel(bookingId, null));

    assertEquals("BOOKING_NOT_FOUND", ex.code());
  }

  @Test
  void aDriverOtherThanTheOneSelectedCannotCancel() {
    stubBooking(UUID.randomUUID(), "CONFIRMED", OffsetDateTime.now().plusHours(2));

    ApiException ex = assertThrows(ApiException.class, () -> controller().cancel(bookingId, null));

    assertEquals("NOT_SELECTED_DRIVER", ex.code());
    assertEquals(HttpStatus.FORBIDDEN, ex.status());
  }

  @Test
  void aBookingAlreadyInProgressCannotBeCancelledByTheDriver() {
    stubBooking(driverId, "IN_PROGRESS", OffsetDateTime.now().plusHours(2));

    ApiException ex = assertThrows(ApiException.class, () -> controller().cancel(bookingId, null));

    assertEquals("DRIVER_CANNOT_CANCEL_NOW", ex.code());
    assertEquals(HttpStatus.CONFLICT, ex.status());
  }

  @Test
  void cancellingWellBeforeDepartureRepublishesForNewOffersWithPriority() {
    stubBooking(driverId, "CONFIRMED", OffsetDateTime.now().plusHours(3));

    Map<String, Object> result = controller().cancel(bookingId, null);

    assertEquals("OPEN_FOR_OFFERS", result.get("status"));
    assertEquals(true, result.get("republished"));
    // Booking must genuinely reopen for offers, driver/offer/PIN cleared --
    // a stale selected_driver_id here would silently block anyone else
    // from ever being selected again.
    verify(db).update(contains("status='OPEN_FOR_OFFERS',selected_offer_id=null"), any(), eq(bookingId));
    verify(db).update(contains("booking.driver_cancelled"), eq(bookingId), eq(bookingId));
    verify(db).update(contains("booking.published"), eq(bookingId), eq(bookingId));
  }

  @Test
  void cancellingWithinTheFifteenMinuteWindowTerminatesTheBookingInstead() {
    stubBooking(driverId, "DRIVER_EN_ROUTE", OffsetDateTime.now().plusMinutes(10));

    Map<String, Object> result = controller().cancel(bookingId, null);

    assertEquals("DRIVER_CANCELLED", result.get("status"));
    assertEquals(false, result.get("republished"));
    verify(db).update(contains("status='DRIVER_CANCELLED'"), eq(bookingId));
    // Only one, urgent event -- never re-published this close to departure.
    verify(db, times(1)).update(contains("booking.driver_cancelled"), eq(bookingId), eq(bookingId));
    verify(db, never()).update(contains("booking.published"), any(), any());
  }

  @Test
  void defaultReasonCodeIsUsedWhenNoneIsSupplied() {
    stubBooking(driverId, "CONFIRMED", OffsetDateTime.now().plusHours(3));

    controller().cancel(bookingId, null);

    verify(db).update(contains("insert into driver_quality_events"), eq(driverId), eq(bookingId), eq("DRIVER_CANCELLED"));
  }

  @Test
  void suppliedReasonCodeIsUsedVerbatimWhenPresent() {
    stubBooking(driverId, "CONFIRMED", OffsetDateTime.now().plusHours(3));

    controller().cancel(bookingId, new DriverCancellationController.CancelRequest("VEHICLE_BREAKDOWN"));

    verify(db).update(contains("insert into driver_quality_events"), eq(driverId), eq(bookingId), eq("VEHICLE_BREAKDOWN"));
  }

  @Test
  void aCapturedOnlinePaymentIsQueuedForRefund() {
    stubBooking(driverId, "CONFIRMED", OffsetDateTime.now().plusHours(3));
    UUID paymentId = UUID.randomUUID();
    when(db.queryForList(contains("from payments"), eq(bookingId))).thenReturn(List.of(Map.of(
        "id", paymentId, "amount_minor", 11000L, "currency", "EUR", "provider", "STRIPE")));

    controller().cancel(bookingId, null);

    verify(db).update(contains("insert into refunds"), eq(paymentId), eq(bookingId), eq(11000L), eq("EUR"), eq("STRIPE"), anyString());
  }

  @Test
  void noRefundIsQueuedWhenNothingWasEverCaptured() {
    // Default stub already returns no captured payments (e.g. a CASH
    // booking, or an ONLINE one never actually paid) -- nothing to refund.
    stubBooking(driverId, "CONFIRMED", OffsetDateTime.now().plusHours(3));

    controller().cancel(bookingId, null);

    verify(db, never()).update(contains("insert into refunds"), any(Object[].class));
  }
}
