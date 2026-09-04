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

    return Map.of(
        "cashDebtMinor", cashDebt,
        "onlinePayableMinor", onlinePayable,
        "currency", "EUR",
        "cashWarning", cashDebt >= 5000,
        "cashRestricted", cashDebt >= 10000,
        "cashBookingsBlocked", cashDebt >= 15000);
  }
}
