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

import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * Gap P1 (GAPS_REQUIRED_CHANGES.md): the wallet endpoint already exposed
 * cashWarning/cashRestricted/cashBookingsBlocked as booleans, but never
 * the actual threshold values (50/100/150€) themselves -- forcing the
 * mobile app to hardcode those amounts to show progress toward the next
 * threshold, which is exactly the financial-rule duplication the
 * guardrails forbid ("ne duplique pas les règles financières critiques
 * dans Flutter"). This only verifies the three new numeric fields are
 * present and correct; the pre-existing boolean logic is unchanged.
 */
@ExtendWith(MockitoExtension.class)
class FinanceControllerWalletThresholdsTest {

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
  void exposesTheNumericThresholdsAlongsideTheExistingBooleans() {
    when(db.queryForObject(contains("driver_platform_debts"), eq(Long.class), eq(driverId))).thenReturn(8000L);
    when(db.queryForObject(contains("driver_payables"), eq(Long.class), eq(driverId))).thenReturn(0L);

    Map<String, Object> result = controller().wallet();

    assertEquals(5000L, result.get("cashWarningThresholdMinor"));
    assertEquals(10000L, result.get("cashRestrictedThresholdMinor"));
    assertEquals(15000L, result.get("cashBlockedThresholdMinor"));
    // 8000 is between the warning (5000) and restricted (10000) thresholds.
    assertEquals(true, result.get("cashWarning"));
    assertEquals(false, result.get("cashRestricted"));
    assertEquals(false, result.get("cashBookingsBlocked"));
  }
}
