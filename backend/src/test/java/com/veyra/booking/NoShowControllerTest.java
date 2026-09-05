package com.veyra.booking;

import com.veyra.finance.CancellationFinanceService;
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
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * Real business rules with zero coverage before: only the driver actually
 * selected for a booking can declare a no-show (not any driver who
 * happens to know the booking id), the booking must genuinely be in
 * DRIVER_ARRIVED, and a mandatory 15-minute wait after the scheduled time
 * must have elapsed -- a driver declaring a customer a no-show
 * immediately on arrival, before giving them any real chance to show up,
 * is exactly the abuse this wait period exists to prevent.
 */
@ExtendWith(MockitoExtension.class)
class NoShowControllerTest {

  @Mock JdbcTemplate db;
  @Mock CancellationFinanceService cancellationFinance;

  private final UUID userId = UUID.randomUUID();
  private final UUID driverId = UUID.randomUUID();
  private final UUID bookingId = UUID.randomUUID();

  @BeforeEach
  void setUpSecurityContext() {
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(userId, null));
    lenient().when(db.queryForObject(eq("select id from drivers where user_id=?"), eq(UUID.class), any(Object[].class)))
        .thenReturn(driverId);
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  private NoShowController controller() {
    return new NoShowController(db, cancellationFinance);
  }

  private void stubBooking(UUID selectedDriverId, String status, OffsetDateTime scheduledAt) {
    when(db.queryForMap(contains("from scheduled_bookings where id=? for update"), eq(bookingId)))
        .thenReturn(Map.of("selected_driver_id", selectedDriverId, "status", status, "scheduled_at", scheduledAt));
  }

  @Test
  void aDifferentDriverThanTheOneSelectedCannotDeclareANoShow() {
    stubBooking(UUID.randomUUID(), "DRIVER_ARRIVED", OffsetDateTime.now().minusMinutes(30));

    ApiException ex = assertThrows(ApiException.class, () -> controller().noShow(bookingId));

    assertEquals("NO_SHOW_NOT_ALLOWED", ex.code());
    assertEquals(HttpStatus.FORBIDDEN, ex.status());
    verifyNoInteractions(cancellationFinance);
  }

  @Test
  void wrongBookingStatusCannotBeDeclaredANoShow() {
    // Selected driver is correct, but the booking never actually reached
    // DRIVER_ARRIVED (e.g. still DRIVER_EN_ROUTE) -- a driver can't
    // declare a no-show for a customer they were never confirmed to have
    // actually reached.
    stubBooking(driverId, "DRIVER_EN_ROUTE", OffsetDateTime.now().minusMinutes(30));

    ApiException ex = assertThrows(ApiException.class, () -> controller().noShow(bookingId));

    assertEquals("NO_SHOW_NOT_ALLOWED", ex.code());
  }

  @Test
  void noShowDeclaredBeforeTheWaitPeriodElapsesIsRejected() {
    // Scheduled 5 minutes ago -- well short of the mandatory 15-minute
    // wait, even though driver/status are both otherwise correct.
    stubBooking(driverId, "DRIVER_ARRIVED", OffsetDateTime.now().minusMinutes(5));

    ApiException ex = assertThrows(ApiException.class, () -> controller().noShow(bookingId));

    assertEquals("WAIT_PERIOD_NOT_FINISHED", ex.code());
    assertEquals(HttpStatus.TOO_EARLY, ex.status());
    // The fee/compensation split must never be computed for a rejected
    // attempt -- calling it here would be premature at best.
    verifyNoInteractions(cancellationFinance);
  }

  @Test
  void validNoShowAfterTheWaitPeriodChargesTheFeeAndUpdatesStatus() {
    stubBooking(driverId, "DRIVER_ARRIVED", OffsetDateTime.now().minusMinutes(20));
    when(cancellationFinance.noShow(bookingId)).thenReturn(
        new CancellationFinanceService.ChargeResult(5000, 4000, 1000, "EUR", false));

    Map<String, Object> result = controller().noShow(bookingId);

    assertEquals("CUSTOMER_NO_SHOW", result.get("status"));
    assertEquals(5000L, result.get("noShowFeeMinor"));
    assertEquals(4000L, result.get("driverCompensationMinor"));
    assertEquals(1000L, result.get("platformAmountMinor"));
    verify(db).update(contains("status='CUSTOMER_NO_SHOW'"), eq(bookingId));
    verify(db).update(contains("insert into outbox_events"), eq(bookingId), eq(bookingId));
  }
}
