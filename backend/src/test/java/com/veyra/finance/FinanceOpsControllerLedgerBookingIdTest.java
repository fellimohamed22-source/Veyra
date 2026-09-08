package com.veyra.finance;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * Real bug found and fixed while wiring D24's "transaction list" (see
 * FinanceControllerTransactionsTest for the read side): both
 * settleDriverDebt() and markPayablePaid() posted their ledger entry with
 * bookingId=null, even though the real booking_id was sitting right there
 * in driver_platform_debts/driver_payables (both UNIQUE NOT NULL columns,
 * confirmed in V001__schema.sql), just never selected into the query. A
 * driver-scoped transaction history joining through
 * scheduled_bookings.selected_driver_id would have silently missed both
 * of these event types -- exactly the two a driver most wants to see
 * ("when was my debt settled", "when did I get paid out").
 */
@ExtendWith(MockitoExtension.class)
class FinanceOpsControllerLedgerBookingIdTest {

  @Mock JdbcTemplate db;
  @Mock LedgerService ledger;

  private FinanceOpsController controller() {
    return new FinanceOpsController(db, ledger);
  }

  @Test
  void settleDriverDebtPostsTheRealBookingIdNotNull() {
    UUID debtId = UUID.randomUUID();
    UUID bookingId = UUID.randomUUID();
    when(db.queryForMap(contains("from driver_platform_debts"), eq(debtId)))
        .thenReturn(Map.of(
            "booking_id", bookingId,
            "amount_minor", 5000L,
            "paid_amount_minor", 0L,
            "currency", "EUR"));

    controller().settleDriverDebt(debtId, 5000L);

    ArgumentCaptor<UUID> bookingIdCaptor = ArgumentCaptor.forClass(UUID.class);
    verify(ledger).post(eq("DRIVER_CASH_DEBT_SETTLED"), bookingIdCaptor.capture(), anyString(), anyString(), anyList());
    assertEquals(bookingId, bookingIdCaptor.getValue());
  }

  @Test
  void markPayablePaidPostsTheRealBookingIdNotNull() {
    UUID payableId = UUID.randomUUID();
    UUID bookingId = UUID.randomUUID();
    when(db.queryForList(contains("from driver_payables"), eq(payableId)))
        .thenReturn(List.of(Map.of(
            "booking_id", bookingId,
            "amount_minor", 12000L,
            "currency", "EUR")));

    controller().markPayablePaid(payableId);

    ArgumentCaptor<UUID> bookingIdCaptor = ArgumentCaptor.forClass(UUID.class);
    verify(ledger).post(eq("DRIVER_PAYABLE_PAID"), bookingIdCaptor.capture(), anyString(), anyString(), anyList());
    assertEquals(bookingId, bookingIdCaptor.getValue());
  }
}
