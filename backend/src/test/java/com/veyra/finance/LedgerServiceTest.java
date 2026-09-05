package com.veyra.finance;

import com.veyra.shared.ApiException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.List;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

/**
 * The single most important invariant in the whole ledger layer: a
 * transaction that doesn't balance must never be written, ever -- these
 * tests exist specifically to prove that failure mode is caught before any
 * database call happens, not just documented in a comment.
 */
@ExtendWith(MockitoExtension.class)
class LedgerServiceTest {

  @Mock JdbcTemplate db;

  @Test
  void balancedEntriesPostSuccessfully() {
    LedgerService ledger = new LedgerService(db);
    when(db.queryForList(anyString(), eq(UUID.class), any(Object[].class)))
        .thenReturn(List.of(UUID.randomUUID()));

    UUID txId = ledger.post("TEST_EVENT", null, "test", "EUR", List.of(
        LedgerService.Entry.debit("DRIVER_PLATFORM_DEBT", 1000),
        LedgerService.Entry.credit("PLATFORM_REVENUE", 1000)));

    assertNotNull(txId);
    // One insert for the transaction header, one per entry (2 entries here).
    verify(db, times(1)).update(contains("insert into ledger_transactions"), any(), any(), any(), any());
    verify(db, times(2)).update(contains("insert into ledger_entries"), any(), any(), any(), any(), any());
  }

  @Test
  void unbalancedEntriesNeverReachTheDatabase() {
    LedgerService ledger = new LedgerService(db);

    ApiException ex = assertThrows(ApiException.class, () -> ledger.post("TEST_EVENT", null, "test", "EUR", List.of(
        LedgerService.Entry.debit("DRIVER_PLATFORM_DEBT", 1000),
        LedgerService.Entry.credit("PLATFORM_REVENUE", 999))));

    assertEquals("LEDGER_UNBALANCED_TRANSACTION", ex.code());
    // The whole point of checking balance before writing anything --
    // confirms no insert of any kind was attempted for a bad transaction.
    verify(db, never()).update(anyString(), any(Object[].class));
    verify(db, never()).update(anyString(), any(), any(), any(), any());
  }

  @Test
  void emptyEntryListRejected() {
    LedgerService ledger = new LedgerService(db);

    assertThrows(ApiException.class, () -> ledger.post("TEST_EVENT", null, "test", "EUR", List.of()));
    verifyNoInteractions(db);
  }

  @Test
  void threeWayBalancedTransactionPostsCorrectly() {
    // Matches the real BOOKING_COMPLETED_ONLINE shape: one debit against
    // two credits that sum to the same total (customer_total_amount_minor
    // = platform_commission_amount_minor + driver_net_amount_minor,
    // enforced elsewhere by booking_financial_snapshots' own CHECK
    // constraint -- this test proves the ledger accepts that exact shape).
    LedgerService ledger = new LedgerService(db);
    when(db.queryForList(anyString(), eq(UUID.class), any(Object[].class)))
        .thenReturn(List.of(UUID.randomUUID()));

    assertDoesNotThrow(() -> ledger.post("BOOKING_COMPLETED_ONLINE", UUID.randomUUID(), "test", "EUR", List.of(
        LedgerService.Entry.debit("PAYMENT_PROCESSOR_CLEARING", 11000),
        LedgerService.Entry.credit("PLATFORM_REVENUE", 1000),
        LedgerService.Entry.credit("DRIVER_PAYABLE", 10000))));
  }

  @Test
  void unknownAccountCodeRejected() {
    LedgerService ledger = new LedgerService(db);
    when(db.queryForList(anyString(), eq(UUID.class), any(Object[].class))).thenReturn(List.of());

    ApiException ex = assertThrows(ApiException.class, () -> ledger.post("TEST_EVENT", null, "test", "EUR", List.of(
        LedgerService.Entry.debit("NOT_A_REAL_ACCOUNT", 500),
        LedgerService.Entry.credit("PLATFORM_REVENUE", 500))));

    assertEquals("LEDGER_UNKNOWN_ACCOUNT_NOT_A_REAL_ACCOUNT", ex.code());
  }
}
