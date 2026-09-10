package com.veyra.booking;

import com.veyra.finance.CancellationFinanceService;
import com.veyra.shared.ApiException;
import org.junit.jupiter.api.AfterEach;
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
 * No test existed at all for this controller before -- the very last
 * of the six files identified while fixing booking_status_history's
 * write side. Single transition: whatever the prior status was ->
 * CANCELLED (customer/partner-initiated cancellation, as opposed to
 * DriverCancellationController's driver-initiated one, already covered
 * separately).
 *
 * Every db call the real cancel() code path actually makes is stubbed
 * here, including ones whose return value the test doesn't otherwise
 * care about (the outbox insert) -- applying the lesson from
 * BookingMaintenanceSchedulerTest's real Mockito strict-stubs failure,
 * where an unstubbed call was flagged as suspiciously similar to an
 * unrelated stub elsewhere in the same test and failed loudly rather
 * than silently no-op'ing.
 */
@ExtendWith(MockitoExtension.class)
class BookingExtraControllerTest {

  @Mock JdbcTemplate db;
  @Mock CancellationFinanceService cancellationFinance;
  @Mock BookingStatusHistoryService history;

  private final UUID bookingId = UUID.randomUUID();
  private final UUID creatorId = UUID.randomUUID();

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  private BookingExtraController controller() {
    return new BookingExtraController(db, cancellationFinance, history);
  }

  private Map<String, Object> bookingRow(String status, Object partnerIdOrNull) {
    Map<String, Object> row = new HashMap<>();
    row.put("creator_user_id", creatorId);
    row.put("partner_id", partnerIdOrNull);
    row.put("scheduled_at", OffsetDateTime.now().plusHours(5));
    row.put("status", status);
    return row;
  }

  @Test
  void theCreatorCancellingRecordsClientAsTheActorType() {
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(creatorId, null));
    when(db.queryForList(contains("from scheduled_bookings where id=? for update"), eq(bookingId)))
        .thenReturn(List.of(bookingRow("CONFIRMED", null)));
    when(cancellationFinance.cancellation(eq(bookingId), anyLong()))
        .thenReturn(new CancellationFinanceService.ChargeResult(0, 0, 0, "EUR", false));
    when(db.update(contains("status='CANCELLED'"), eq(bookingId))).thenReturn(1);
    when(db.update(contains("into outbox_events"), eq(bookingId), eq(bookingId))).thenReturn(1);

    controller().cancel(bookingId);

    verify(history).record(bookingId, "CONFIRMED", "CANCELLED", "CLIENT", creatorId, null);
  }

  @Test
  void aPartnerBookingRecordsPartnerAsTheActorType() {
    UUID partnerId = UUID.randomUUID();
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(creatorId, null));
    when(db.queryForList(contains("from scheduled_bookings where id=? for update"), eq(bookingId)))
        .thenReturn(List.of(bookingRow("OFFERS_RECEIVED", partnerId)));
    when(cancellationFinance.cancellation(eq(bookingId), anyLong()))
        .thenReturn(new CancellationFinanceService.ChargeResult(0, 0, 0, "EUR", false));
    when(db.update(contains("status='CANCELLED'"), eq(bookingId))).thenReturn(1);
    when(db.update(contains("into outbox_events"), eq(bookingId), eq(bookingId))).thenReturn(1);

    controller().cancel(bookingId);

    verify(history).record(bookingId, "OFFERS_RECEIVED", "CANCELLED", "PARTNER", creatorId, null);
  }

  @Test
  void anAlreadyInProgressBookingCannotBeCancelledAndNoHistoryIsRecorded() {
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(creatorId, null));
    when(db.queryForList(contains("from scheduled_bookings where id=? for update"), eq(bookingId)))
        .thenReturn(List.of(bookingRow("IN_PROGRESS", null)));

    ApiException ex = assertThrows(ApiException.class, () -> controller().cancel(bookingId));

    assertEquals("CANNOT_CANCEL", ex.code());
    verifyNoInteractions(history);
    verifyNoInteractions(cancellationFinance);
  }

  @Test
  void previewReturnsTheServiceComputedFeeWithoutCancellingAnything() {
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(creatorId, null));
    when(db.queryForList(eq("select creator_user_id,partner_id,scheduled_at,status from scheduled_bookings where id=?"), eq(bookingId)))
        .thenReturn(List.of(bookingRow("CONFIRMED", null)));
    when(cancellationFinance.previewCancellation(eq(bookingId), anyLong()))
        .thenReturn(new CancellationFinanceService.Preview(1200, "EUR", false));

    Map<String, Object> result = controller().cancellationPreview(bookingId);

    assertEquals(1200L, result.get("cancellationFeeMinor"));
    assertEquals("EUR", result.get("currency"));
    assertEquals(false, result.get("free"));
    // The whole point of a preview: never touches the booking's own
    // status or writes anything, regardless of how the fee comes out.
    verify(db, never()).update(anyString(), any(Object[].class));
    verifyNoInteractions(history);
  }

  @Test
  void previewOnAnAlreadyTerminalBookingIsRejectedTheSameWayCancelItselfWouldBe() {
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(creatorId, null));
    when(db.queryForList(eq("select creator_user_id,partner_id,scheduled_at,status from scheduled_bookings where id=?"), eq(bookingId)))
        .thenReturn(List.of(bookingRow("COMPLETED", null)));

    ApiException ex = assertThrows(ApiException.class, () -> controller().cancellationPreview(bookingId));

    assertEquals("CANNOT_CANCEL", ex.code());
    verifyNoInteractions(cancellationFinance);
  }

  @Test
  void previewRejectsSomeoneWhoIsNeitherTheCreatorNorAuthorizedPartnerStaff() {
    UUID someoneElse = UUID.randomUUID();
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(someoneElse, null));
    when(db.queryForList(eq("select creator_user_id,partner_id,scheduled_at,status from scheduled_bookings where id=?"), eq(bookingId)))
        .thenReturn(List.of(bookingRow("CONFIRMED", null)));

    ApiException ex = assertThrows(ApiException.class, () -> controller().cancellationPreview(bookingId));

    assertEquals("FORBIDDEN", ex.code());
  }
}
