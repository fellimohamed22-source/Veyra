package com.veyra.booking;

import com.veyra.finance.LedgerService;
import com.veyra.security.PinCrypto;
import com.veyra.shared.ApiException;
import org.junit.jupiter.api.*;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

// Endpoint-level business tests; these do not certify PostgreSQL locking or rollback.
class BookingLifecycleTest {
  final UUID user = UUID.randomUUID(), driver = UUID.randomUUID(), booking = UUID.randomUUID();
  final JdbcTemplate db = mock(JdbcTemplate.class);
  final PasswordEncoder encoder = mock(PasswordEncoder.class);
  final LedgerService ledger = mock(LedgerService.class);
  final BookingStatusHistoryService history = mock(BookingStatusHistoryService.class);
  final BookingController controller = new BookingController(db, encoder, mock(PinCrypto.class),
      ledger, 120, 24, 60, 30, history);
  final Map<String,Object> state = new HashMap<>();

  @BeforeEach void setup() {
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(user, null));
    state.put("selected_driver_id", driver);
    state.put("status", "CONFIRMED");
    state.put("pin_hash", "hash");
    state.put("pin_failed_attempts", 0);
    when(db.queryForList(eq("select id from drivers where user_id=?"), eq(UUID.class), eq(user)))
        .thenReturn(List.of(driver));
    when(db.queryForList(contains("from scheduled_bookings where id=? for update"), eq(booking)))
        .thenAnswer(invocation -> List.of(new HashMap<>(state)));
    // Driver's last tracked position is within the pickup radius (DEC-10).
    when(db.queryForList(contains("current_driver_locations"), eq(Boolean.class), any(Object[].class)))
        .thenReturn(List.of(true));
    doAnswer(invocation -> { state.put("status", invocation.getArgument(1)); return 1; })
        .when(db).update(eq("update scheduled_bookings set status=?,updated_at=now() where id=?"),
            anyString(), eq(booking));
  }
  @AfterEach void cleanup() { SecurityContextHolder.clearContext(); }

  @Test void anotherDriverCannotAdvanceTheRide() {
    state.put("selected_driver_id", UUID.randomUUID());
    assertEquals("NOT_SELECTED_DRIVER", assertThrows(ApiException.class,
        () -> controller.enroute(booking)).code());
    assertEquals("CONFIRMED", state.get("status"));
    verifyNoInteractions(history, ledger);
    verify(db, never()).update(anyString(), any(Object[].class));
  }

  @Test void arrivalCannotSkipDeparture() {
    assertEquals("INVALID_BOOKING_TRANSITION", assertThrows(ApiException.class,
        () -> controller.arrived(booking)).code());
    assertEquals("CONFIRMED", state.get("status"));
    verifyNoInteractions(history, ledger);
  }

  @Test void validPinCannotStartAnUnpaidOnlineRideButCapturedPaymentCan() {
    state.put("status", "DRIVER_ARRIVED");
    when(encoder.matches("0427", "hash")).thenReturn(true);
    when(db.queryForObject(contains("select payment_method"), eq(String.class), eq(booking)))
        .thenReturn("ONLINE");
    when(db.queryForObject(contains("status='CAPTURED'"), eq(Integer.class), eq(booking)))
        .thenReturn(0, 1);
    assertEquals("PAYMENT_REQUIRED", assertThrows(ApiException.class,
        () -> controller.start(booking, new BookingController.Pin("0427"))).code());
    assertEquals("DRIVER_ARRIVED", state.get("status"));
    verifyNoInteractions(history, ledger);
    controller.start(booking, new BookingController.Pin("0427"));
    assertEquals("IN_PROGRESS", state.get("status"));
    verify(history).record(booking, "DRIVER_ARRIVED", "IN_PROGRESS", "DRIVER", user, null);
  }

  @ParameterizedTest @ValueSource(strings = {"CASH", "ONLINE", "PARTNER_INVOICE"})
  void completeJourneyPostsTheCorrectSettlementOnce(String method) {
    when(encoder.matches("0427", "hash")).thenReturn(true);
    when(db.queryForObject(contains("select payment_method"), eq(String.class), eq(booking)))
        .thenReturn(method);
    if(method.equals("ONLINE")) {
      when(db.queryForObject(contains("status='CAPTURED'"), eq(Integer.class), eq(booking)))
          .thenReturn(1);
    }
    when(db.queryForList(contains("join booking_financial_snapshots"), eq(booking)))
        .thenReturn(List.of(Map.of("payment_method", method, "selected_driver_id", driver,
            "platform_commission_amount_minor", 1500L, "driver_net_amount_minor", 10000L,
            "customer_total_amount_minor", 11500L, "currency", "EUR")));
    controller.enroute(booking);
    controller.arrived(booking);
    controller.start(booking, new BookingController.Pin("0427"));
    controller.complete(booking);
    assertEquals("COMPLETED", state.get("status"));
    for(String[] transition : List.of(new String[]{"CONFIRMED", "DRIVER_EN_ROUTE"},
        new String[]{"DRIVER_EN_ROUTE", "DRIVER_ARRIVED"},
        new String[]{"DRIVER_ARRIVED", "IN_PROGRESS"}, new String[]{"IN_PROGRESS", "COMPLETED"})) {
      verify(history).record(booking, transition[0], transition[1], "DRIVER", user, null);
      verify(db).update(contains("insert into outbox_events"), eq(booking),
          eq("booking.status." + transition[1].toLowerCase(Locale.ROOT)), eq(booking));
    }
    List<LedgerService.Entry> entries;
    if(method.equals("CASH")) {
      entries = List.of(LedgerService.Entry.debit("DRIVER_PLATFORM_DEBT", 1500),
          LedgerService.Entry.credit("PLATFORM_REVENUE", 1500));
      verify(db).update(contains("insert into driver_platform_debts"), eq(driver), eq(booking), eq(1500L), eq("EUR"));
      verify(db, never()).update(contains("insert into driver_payables"), any(), any(), any(), any());
    } else {
      entries = List.of(LedgerService.Entry.debit(method.equals("ONLINE") ? "PAYMENT_PROCESSOR_CLEARING" : "PARTNER_RECEIVABLE", 11500),
          LedgerService.Entry.credit("PLATFORM_REVENUE", 1500), LedgerService.Entry.credit("DRIVER_PAYABLE", 10000));
      verify(db).update(contains("insert into driver_payables"), eq(driver), eq(booking), eq(10000L), eq("EUR"));
      verify(db, never()).update(contains("insert into driver_platform_debts"), any(), any(), any(), any());
    }
    assertEquals("INVALID_BOOKING_TRANSITION", assertThrows(ApiException.class,
        () -> controller.complete(booking)).code());
    verify(ledger, times(1)).post(eq("BOOKING_COMPLETED_" + method), eq(booking), anyString(), eq("EUR"), eq(entries));
    verifyNoMoreInteractions(ledger);
  }
}
