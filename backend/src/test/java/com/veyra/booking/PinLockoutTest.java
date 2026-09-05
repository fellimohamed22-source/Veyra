package com.veyra.booking;

import com.veyra.finance.LedgerService;
import com.veyra.security.CurrentUser;
import com.veyra.security.PinCrypto;
import com.veyra.shared.ApiException;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * Security-critical state machine that had zero coverage: PinCryptoTest
 * only tests the hashing primitive, never this lockout logic
 * (BookingController.driverTransition, exercised here through the real
 * public start() endpoint since driverTransition() itself is private).
 * A bug here would either let a PIN be brute-forced (no real lockout) or
 * lock a legitimate driver out on a false trigger -- both are real
 * incidents, not edge cases.
 */
@ExtendWith(MockitoExtension.class)
class PinLockoutTest {

  @Mock JdbcTemplate db;
  @Mock PasswordEncoder enc;
  @Mock PinCrypto pinCrypto;
  @Mock LedgerService ledger;

  private final UUID userId = UUID.randomUUID();
  private final UUID driverId = UUID.randomUUID();
  private final UUID bookingId = UUID.randomUUID();

  @BeforeEach
  void setUpSecurityContext() {
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(userId, null));
  }

  @AfterEach
  void clearSecurityContext() {
    // SecurityContextHolder is thread-local/static -- must be cleared so
    // this test's fake principal can never leak into an unrelated test.
    SecurityContextHolder.clearContext();
  }

  private BookingController controller() {
    return new BookingController(db, enc, pinCrypto, ledger, 30L, 24L, 60L, 30L);
  }

  private void stubDriverLookup() {
    when(db.queryForList(eq("select id from drivers where user_id=?"), eq(UUID.class), any(Object[].class)))
        .thenReturn(List.of(driverId));
  }

  private void stubBookingRow(int failedAttempts, OffsetDateTime lockedUntil) {
    Map<String, Object> row = new java.util.HashMap<>();
    row.put("selected_driver_id", driverId);
    row.put("status", "DRIVER_ARRIVED");
    row.put("pin_hash", "some-hash");
    row.put("pin_failed_attempts", failedAttempts);
    row.put("pin_locked_until", lockedUntil);
    when(db.queryForList(contains("from scheduled_bookings where id=? for update"), any(Object[].class)))
        .thenReturn(List.of(row));
  }

  @Test
  void wrongPinBelowThresholdIncrementsAttemptsAndRejects() {
    stubDriverLookup();
    stubBookingRow(2, null);
    when(enc.matches(eq("1234"), eq("some-hash"))).thenReturn(false);

    ApiException ex = assertThrows(ApiException.class,
        () -> controller().start(bookingId, new BookingController.Pin("1234")));

    assertEquals("INVALID_PIN", ex.code());

    ArgumentCaptor<Object[]> args = ArgumentCaptor.forClass(Object[].class);
    verify(db).update(contains("pin_failed_attempts=?,pin_locked_until=?"), args.capture());
    // 3rd wrong attempt (was 2, now 3) -- still below the 5-attempt lock threshold.
    assertEquals(3, args.getValue()[0]);
    assertNull(args.getValue()[1]);
  }

  @Test
  void fifthWrongPinLocksForFifteenMinutesInsteadOfJustRejecting() {
    stubDriverLookup();
    stubBookingRow(4, null);
    when(enc.matches(eq("0000"), eq("some-hash"))).thenReturn(false);

    ApiException ex = assertThrows(ApiException.class,
        () -> controller().start(bookingId, new BookingController.Pin("0000")));

    // The 5th failure is a materially different error than the first four --
    // the driver needs to know they're locked out, not just "wrong code,
    // try again", since trying again immediately would be pointless.
    assertEquals("PIN_TEMPORARILY_LOCKED", ex.code());

    ArgumentCaptor<Object[]> args = ArgumentCaptor.forClass(Object[].class);
    verify(db).update(contains("pin_failed_attempts=?,pin_locked_until=?"), args.capture());
    assertEquals(5, args.getValue()[0]);
    assertNotNull(args.getValue()[1]);
    OffsetDateTime lockUntil = (OffsetDateTime) args.getValue()[1];
    assertTrue(lockUntil.isAfter(OffsetDateTime.now().plusMinutes(14)));
    assertTrue(lockUntil.isBefore(OffsetDateTime.now().plusMinutes(16)));
  }

  @Test
  void alreadyLockedBookingRejectsBeforeEvenCheckingThePin() {
    stubDriverLookup();
    stubBookingRow(5, OffsetDateTime.now().plusMinutes(10));

    ApiException ex = assertThrows(ApiException.class,
        () -> controller().start(bookingId, new BookingController.Pin("1234")));

    assertEquals("PIN_TEMPORARILY_LOCKED", ex.code());
    // The real point of this test: a currently-locked booking must reject
    // immediately, without ever calling enc.matches() at all -- otherwise
    // a locked-out attacker could still learn whether each guess was right
    // or wrong via timing/behavior, even while "locked".
    verifyNoInteractions(enc);
  }

  @Test
  void lockThatHasAlreadyExpiredAllowsANewAttempt() {
    stubDriverLookup();
    stubBookingRow(5, OffsetDateTime.now().minusMinutes(1));
    when(enc.matches(eq("1234"), eq("some-hash"))).thenReturn(false);

    ApiException ex = assertThrows(ApiException.class,
        () -> controller().start(bookingId, new BookingController.Pin("1234")));

    // An expired lock must not behave like an active one -- this attempt
    // is evaluated as a real PIN check, not rejected outright.
    assertEquals("INVALID_PIN", ex.code());
    verify(enc).matches(eq("1234"), eq("some-hash"));
  }
}
