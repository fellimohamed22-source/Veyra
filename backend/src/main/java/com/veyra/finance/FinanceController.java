package com.veyra.finance;

import com.veyra.security.CurrentUser;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

import java.util.*;

@RestController
@RequestMapping("/api/v1")
public class FinanceController {
  private final JdbcTemplate db;

  public FinanceController(JdbcTemplate db) {
    this.db = db;
  }

  @GetMapping("/driver/wallet")
  public Map<String, Object> wallet() {
    UUID driverId = db.queryForObject(
        "select id from drivers where user_id=?",
        UUID.class,
        CurrentUser.id());

    Long debt = db.queryForObject(
        "select coalesce(sum(amount_minor-paid_amount_minor),0) " +
        "from driver_platform_debts where driver_id=? " +
        "and status in ('DUE','PARTIALLY_PAID','OVERDUE')",
        Long.class,
        driverId);

    Long payable = db.queryForObject(
        "select coalesce(sum(amount_minor),0) " +
        "from driver_payables where driver_id=? and status='PAYABLE'",
        Long.class,
        driverId);

    long cashDebt = debt == null ? 0 : debt;
    long onlinePayable = payable == null ? 0 : payable;

    // Gap P1 (GAPS_REQUIRED_CHANGES.md): booleans alone (cashWarning /
    // cashRestricted / cashBookingsBlocked) tell the UI which state
    // applies, but not the actual threshold values -- forcing the mobile
    // app to hardcode 50/100/150€ itself to show e.g. "80€ / 100€ before
    // restriction", which is exactly the kind of financial-rule
    // duplication the guardrails forbid. Exposing the same three
    // constants used to compute the booleans below so the UI never has
    // to guess or hardcode them.
    long warningThreshold=5000,restrictedThreshold=10000,blockedThreshold=15000;

    Map<String,Object> result=new LinkedHashMap<>();
    result.put("cashDebtMinor", cashDebt);
    result.put("onlinePayableMinor", onlinePayable);
    result.put("currency", "EUR");
    result.put("cashWarning", cashDebt >= warningThreshold);
    result.put("cashRestricted", cashDebt >= restrictedThreshold);
    result.put("cashBookingsBlocked", cashDebt >= blockedThreshold);
    result.put("cashWarningThresholdMinor", warningThreshold);
    result.put("cashRestrictedThresholdMinor", restrictedThreshold);
    result.put("cashBlockedThresholdMinor", blockedThreshold);
    return result;
  }
}
