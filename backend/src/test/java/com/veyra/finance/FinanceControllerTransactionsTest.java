package com.veyra.finance;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
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
 * Gap flagged in the D24 fiche (GAP UX/API: "/driver/wallet doit exposer
 * clairement les seuils et payables" -- thresholds already covered by
 * FinanceControllerWalletThresholdsTest; this covers the separately
 * missing "transaction list" UI component, backed by ledger_entries/
 * ledger_transactions which previously had no read path at all).
 */
@ExtendWith(MockitoExtension.class)
class FinanceControllerTransactionsTest {

  @Mock JdbcTemplate db;

  private final UUID userId = UUID.randomUUID();
  private final UUID driverId = UUID.randomUUID();

  @BeforeEach
  void setUpSecurityContext() {
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(userId, null));
    when(db.queryForObject(eq("select id from drivers where user_id=?"), eq(UUID.class), eq(userId)))
        .thenReturn(driverId);
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  private FinanceController controller() {
    return new FinanceController(db);
  }

  @Test
  void scopesStrictlyToTheCallingDriverAndTheirTwoOwnAccounts() {
    when(db.queryForList(anyString(), eq(driverId)))
        .thenReturn(List.of(Map.of("event_type", "BOOKING_COMPLETED_CASH", "amount_minor", 1500L)));

    List<Map<String, Object>> result = controller().transactions();

    assertEquals(1, result.size());
    ArgumentMatcher<String> hasExpectedShape = sql ->
        sql.contains("where sb.selected_driver_id=?") &&
        sql.contains("a.code in ('DRIVER_PAYABLE','DRIVER_PLATFORM_DEBT')") &&
        // The join through scheduled_bookings is exactly what makes
        // DRIVER_CASH_DEBT_SETTLED/DRIVER_PAYABLE_PAID visible at all
        // now that FinanceOpsController supplies a real booking_id --
        // this line existing at all is the regression guard for that.
        sql.contains("join scheduled_bookings sb on sb.id=lt.booking_id");
    verify(db).queryForList(argThat(hasExpectedShape), eq(driverId));
  }

  @Test
  void neverExposesThePlatformsOwnCounterAccounts() {
    // A booking-completion transaction has entries on BOTH
    // DRIVER_PLATFORM_DEBT/DRIVER_PAYABLE (the driver's side) AND
    // PLATFORM_REVENUE/PAYMENT_PROCESSOR_CLEARING/PARTNER_RECEIVABLE (the
    // platform's side) in the same ledger_transactions row -- the SQL's
    // account filter is what's solely responsible for the driver never
    // seeing the platform-only half. Re-assert the exact filter clause
    // rather than trying to fake a real join in a mocked unit test.
    when(db.queryForList(anyString(), eq(driverId))).thenReturn(List.of());

    controller().transactions();

    verify(db).queryForList(
        argThat(sql -> sql.contains("'DRIVER_PAYABLE','DRIVER_PLATFORM_DEBT'") &&
            !sql.contains("PLATFORM_REVENUE") &&
            !sql.contains("PAYMENT_PROCESSOR_CLEARING") &&
            !sql.contains("PARTNER_RECEIVABLE")),
        eq(driverId));
  }
}
