package com.veyra.booking;

import com.veyra.shared.ApiException;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.time.OffsetDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * Real, consequential logic with zero coverage before: who's allowed to
 * modify a booking (the creator, or active staff of the partner that
 * created it -- never anyone else), which statuses even permit
 * modification, the lead-time floor on structural changes, and the
 * distinction between a structural edit (re-opens the booking for fresh
 * offers, expiring existing ones) versus a notes-only edit (which must
 * never re-trigger any of that).
 */
@ExtendWith(MockitoExtension.class)
class BookingModificationControllerTest {

  @Mock JdbcTemplate db;

  private final UUID userId = UUID.randomUUID();
  private final UUID bookingId = UUID.randomUUID();

  @BeforeEach
  void setUpSecurityContext() {
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(userId, null));
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  private BookingModificationController controller() {
    return new BookingModificationController(db, 30L, 24L, 60L, 30L);
  }

  private Map<String, Object> bookingRow(UUID creatorId, UUID partnerId, String status, OffsetDateTime scheduledAt) {
    Map<String, Object> row = new HashMap<>();
    row.put("creator_user_id", creatorId);
    row.put("partner_id", partnerId);
    row.put("status", status);
    row.put("scheduled_at", scheduledAt);
    return row;
  }

  private void stubBooking(Map<String, Object> row) {
    when(db.queryForList(contains("from scheduled_bookings where id=? for update"), eq(bookingId)))
        .thenReturn(List.of(row));
  }

  private void stubFinalReadBack() {
    when(db.queryForMap(contains("select id,pickup_address"), eq(bookingId)))
        .thenReturn(Map.of("id", bookingId, "status", "OPEN_FOR_OFFERS"));
  }

  @Test
  void unknownBookingRejected() {
    when(db.queryForList(contains("from scheduled_bookings where id=? for update"), eq(bookingId))).thenReturn(List.of());

    ApiException ex = assertThrows(ApiException.class, () -> controller().update(
        bookingId, new BookingModificationController.UpdateRequest(null, null, null, null, null, null, "note")));

    assertEquals("BOOKING_NOT_FOUND", ex.code());
  }

  @Test
  void someoneWhoIsNeitherTheCreatorNorPartnerStaffCannotModifyIt() {
    UUID otherUser = UUID.randomUUID();
    UUID partnerId = UUID.randomUUID();
    stubBooking(bookingRow(otherUser, partnerId, "OPEN_FOR_OFFERS", OffsetDateTime.now().plusHours(5)));
    when(db.queryForObject(contains("from partner_users"), eq(Integer.class), eq(partnerId), eq(userId))).thenReturn(0);

    ApiException ex = assertThrows(ApiException.class, () -> controller().update(
        bookingId, new BookingModificationController.UpdateRequest(null, null, null, null, null, null, "note")));

    assertEquals("FORBIDDEN", ex.code());
  }

  @Test
  void activePartnerStaffCanModifyABookingTheyDidNotPersonallyCreate() {
    UUID otherUser = UUID.randomUUID();
    UUID partnerId = UUID.randomUUID();
    stubBooking(bookingRow(otherUser, partnerId, "OPEN_FOR_OFFERS", OffsetDateTime.now().plusHours(5)));
    when(db.queryForObject(contains("from partner_users"), eq(Integer.class), eq(partnerId), eq(userId))).thenReturn(1);
    stubFinalReadBack();

    assertDoesNotThrow(() -> controller().update(
        bookingId, new BookingModificationController.UpdateRequest(null, null, null, null, null, null, "updated note")));

    verify(db).update(contains("customer_notes=?"), eq("updated note"), eq(bookingId));
  }

  @Test
  void aBookingAlreadyConfirmedCannotBeModifiedInPlace() {
    stubBooking(bookingRow(userId, null, "CONFIRMED", OffsetDateTime.now().plusHours(5)));

    ApiException ex = assertThrows(ApiException.class, () -> controller().update(
        bookingId, new BookingModificationController.UpdateRequest(null, null, null, null, null, null, "note")));

    assertEquals("BOOKING_MODIFICATION_REQUIRES_CANCEL_RECREATE", ex.code());
  }

  @Test
  void aStructuralChangeTooCloseToDepartureIsRejected() {
    // min lead time configured at 30 minutes; requesting a new schedule
    // only 10 minutes out is a structural change (scheduledAt is one of
    // the fields that triggers the structural path).
    stubBooking(bookingRow(userId, null, "OPEN_FOR_OFFERS", OffsetDateTime.now().plusHours(5)));

    ApiException ex = assertThrows(ApiException.class, () -> controller().update(
        bookingId, new BookingModificationController.UpdateRequest(
            null, null, OffsetDateTime.now().plusMinutes(10), null, null, null, null)));

    assertEquals("LEAD_TIME_TOO_SHORT", ex.code());
  }

  @Test
  void aNotesOnlyChangeNeverReopensOffersOrChecksLeadTime() {
    // Scheduled only 5 minutes out -- would fail the lead-time check if
    // treated as structural, but a notes-only edit must never even reach
    // that check at all.
    stubBooking(bookingRow(userId, null, "OFFERS_RECEIVED", OffsetDateTime.now().plusMinutes(5)));
    stubFinalReadBack();

    assertDoesNotThrow(() -> controller().update(
        bookingId, new BookingModificationController.UpdateRequest(null, null, null, null, null, null, "just a note")));

    verify(db, never()).update(contains("status='OPEN_FOR_OFFERS'"), any(), any());
    verify(db, never()).update(contains("driver_offers set status='EXPIRED'"), eq(bookingId));
  }

  @Test
  void aValidStructuralChangeExpiresExistingOffersAndRepublishes() {
    stubBooking(bookingRow(userId, null, "OPEN_FOR_OFFERS", OffsetDateTime.now().plusHours(5)));
    stubFinalReadBack();

    controller().update(bookingId, new BookingModificationController.UpdateRequest(
        null, null, null, null, 3, null, null));

    verify(db).update(contains("passenger_count=?"), eq(3), eq(bookingId));
    verify(db).update(contains("driver_offers set status='EXPIRED'"), eq(bookingId));
    verify(db).update(contains("status='OPEN_FOR_OFFERS'"), any(), eq(bookingId));
    verify(db).update(contains("booking.published"), eq(bookingId), eq(bookingId));
  }
}
