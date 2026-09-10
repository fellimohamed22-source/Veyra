package com.veyra.finance;

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
 * confirmed in V001__schema.sql), just never selected into the query.
 *
 * Second time writing this test: the first attempt (committed, then
 * reverted after an undiagnosable CI failure earlier this session) never
 * set up SecurityContextHolder authentication at all. Both
 * settleDriverDebt() and markPayablePaid() call audit() internally,
 * which calls CurrentUser.id() directly -- not gated by @PreAuthorize
 * (which doesn't apply in a raw unit test anyway, confirmed established
 * pattern throughout this test suite), so it runs unconditionally and
 * throws a NullPointerException the moment
 * SecurityContextHolder.getContext().getAuthentication() is null, before
 * ledger.post() -- the very interaction being verified -- is ever
 * reached. Traced audit()'s own code (db.update + CurrentUser.id()) by
 * hand this time, and added a stub for its db.update() call too rather
 * than assuming an unstubbed one is automatically safe (it returns a
 * primitive int, defaulting to 0, so it is safe here -- but stubbing it
 * explicitly keeps this test's intent legible rather than relying on
 * that Mockito default going unnoticed).
 */
@ExtendWith(MockitoExtension.class)
class FinanceOpsControllerLedgerBookingIdTest {

  @Mock JdbcTemplate db;
  @Mock LedgerService ledger;

  private final UUID actorId = UUID.randomUUID();

  @BeforeEach
  void setUpSecurityContext() {
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(actorId, null));
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

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
    when(db.update(contains("update driver_platform_debts"), anyLong(), anyString(), eq(debtId)))
        .thenReturn(1);
    when(db.update(contains("into audit_logs"), eq(actorId), anyString(), anyString(), eq(debtId)))
        .thenReturn(1);

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
    when(db.update(contains("update driver_payables"), eq(payableId)))
        .thenReturn(1);
    when(db.update(contains("into audit_logs"), eq(actorId), anyString(), anyString(), eq(payableId)))
        .thenReturn(1);

    controller().markPayablePaid(payableId);

    ArgumentCaptor<UUID> bookingIdCaptor = ArgumentCaptor.forClass(UUID.class);
    verify(ledger).post(eq("DRIVER_PAYABLE_PAID"), bookingIdCaptor.capture(), anyString(), anyString(), anyList());
    assertEquals(bookingId, bookingIdCaptor.getValue());
  }
}
