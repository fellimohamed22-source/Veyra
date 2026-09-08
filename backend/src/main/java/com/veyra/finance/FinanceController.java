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

  // Gap explicitly flagged in the UI kit (D24 fiche: "transaction list"
  // listed as a required UI component, ledger_transactions/ledger_entries
  // listed as the source of truth) -- LedgerService could only write,
  // nothing ever read a driver's own history back out.
  //
  // Two of the five real posting events (DRIVER_CASH_DEBT_SETTLED,
  // DRIVER_PAYABLE_PAID) used to post with bookingId=null even though the
  // real booking_id was sitting right there, unselected, in
  // driver_platform_debts/driver_payables -- fixed in the same change as
  // this endpoint (FinanceOpsController), since without that fix this
  // query would silently miss exactly the two event types a driver most
  // wants to see ("when was my debt settled", "when did I get paid out").
  //
  // Scoped to only the two accounts that represent this driver's own
  // side of any transaction (DRIVER_PAYABLE, DRIVER_PLATFORM_DEBT) --
  // never the platform's own counter-entry on the same transaction
  // (PLATFORM_REVENUE, PAYMENT_PROCESSOR_CLEARING, PARTNER_RECEIVABLE),
  // which is none of this driver's business to see.
  @GetMapping("/driver/wallet/transactions")
  public List<Map<String,Object>> transactions() {
    UUID driverId = db.queryForObject(
        "select id from drivers where user_id=?",
        UUID.class,
        CurrentUser.id());

    return db.queryForList(
        "select lt.id,lt.event_type,lt.description,lt.booking_id,lt.created_at," +
        "le.direction,le.amount_minor,le.currency,a.code as account_code " +
        "from ledger_entries le " +
        "join ledger_transactions lt on lt.id=le.transaction_id " +
        "join ledger_accounts a on a.id=le.account_id " +
        "join scheduled_bookings sb on sb.id=lt.booking_id " +
        "where sb.selected_driver_id=? and a.code in ('DRIVER_PAYABLE','DRIVER_PLATFORM_DEBT') " +
        "order by lt.created_at desc limit 200",
        driverId);
  }
}
