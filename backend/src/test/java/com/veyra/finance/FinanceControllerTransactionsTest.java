package com.veyra.finance;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentMatcher;
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
 * Second attempt: the first version of this exact test class was
 * reverted alongside FinanceOpsControllerLedgerBookingIdTest earlier
 * this session after an undiagnosable CI failure -- but on review this
 * class's own SecurityContextHolder setup and call tracing both look
 * correct (unlike the OTHER file, which never set up authentication at
 * all despite the controller code it exercises calling audit() ->
 * CurrentUser.id() internally). Most likely FinanceOpsController
 * LedgerBookingIdTest was the actual failing file and this one was an
 * innocent casualty of reverting both together without being able to
 * tell which one broke the build. Re-traced transactions()'s exact two
 * calls (queryForObject for driverId, then queryForList for the
 * transaction rows) against this test's stubs once more before
 * recommitting, rather than assuming the original was fine just because
 * it "looks right" a second time.
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
        sql.contains("join scheduled_bookings sb on sb.id=lt.booking_id");
    verify(db).queryForList(argThat(hasExpectedShape), eq(driverId));
  }

  @Test
  void neverExposesThePlatformsOwnCounterAccounts() {
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
