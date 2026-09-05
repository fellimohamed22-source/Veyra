package com.veyra.finance;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.when;

/**
 * Zero coverage existed for this before -- real financial math (percentage
 * fees, minimum/maximum caps, driver/platform split) that a rounding or
 * off-by-one bug in would misbill either a customer or a driver. Tests the
 * real charge() method through a mocked JdbcTemplate rather than
 * reimplementing the formula inline (unlike CommissionFormulaTest's
 * pure-function style) -- charge() branches on payment method and touches
 * three different tables, so the actual method needs exercising, not just
 * its arithmetic core.
 */
@ExtendWith(MockitoExtension.class)
class CancellationFinanceServiceTest {

  @Mock JdbcTemplate db;

  private Map<String, Object> policy() {
    return Map.ofEntries(
        Map.entry("id", UUID.randomUUID()),
        Map.entry("free_until_minutes", 1440),
        Map.entry("mid_window_from_minutes", 120),
        Map.entry("mid_fee_bps", 3000),
        Map.entry("driver_share_mid_bps", 5000),
        Map.entry("mid_fee_min_minor", 500),
        Map.entry("late_fee_bps", 8000),
        Map.entry("driver_share_late_bps", 7000),
        Map.entry("no_show_fee_bps", 10000),
        Map.entry("driver_share_no_show_bps", 8000),
        Map.entry("no_show_cap_minor", 5000L));
  }

  private void stubPolicyAndBooking(UUID bookingId, UUID driverId, long driverProposedAmountMinor, String paymentMethod) {
    when(db.queryForList(contains("cancellation_policy_versions"))).thenReturn(List.of(policy()));
    when(db.queryForList(contains("from scheduled_bookings sb left join booking_financial_snapshots"), any(Object[].class)))
        .thenReturn(List.of(Map.of(
            "payment_method", paymentMethod,
            "creator_user_id", UUID.randomUUID(),
            "selected_driver_id", driverId,
            "driver_proposed_amount_minor", driverProposedAmountMinor,
            "customer_total_amount_minor", driverProposedAmountMinor + 700,
            "currency", "EUR")));
  }

  @Test
  void cancellationWellBeforeFreeWindowChargesNothing() {
    CancellationFinanceService svc = new CancellationFinanceService(db);
    UUID bookingId = UUID.randomUUID();
    stubPolicyAndBooking(bookingId, UUID.randomUUID(), 10000, "ONLINE");

    // free_until_minutes = 1440 -- well beyond that, no fee at all.
    CancellationFinanceService.ChargeResult result = svc.cancellation(bookingId, 2000);

    assertEquals(0, result.feeMinor());
    assertEquals(0, result.driverCompensationMinor());
    assertEquals(0, result.platformAmountMinor());
    assertFalse(result.refundQueued());
  }

  @Test
  void midWindowCancellationSplitsFeeBetweenDriverAndPlatform() {
    CancellationFinanceService svc = new CancellationFinanceService(db);
    UUID bookingId = UUID.randomUUID();
    stubPolicyAndBooking(bookingId, UUID.randomUUID(), 10000, "CASH");

    // Between mid_window_from_minutes (120) and free_until_minutes (1440).
    CancellationFinanceService.ChargeResult result = svc.cancellation(bookingId, 600);

    // mid_fee_bps=3000 (30%) of 10000 = 3000; driver_share_mid_bps=5000 (50%) of 3000 = 1500.
    assertEquals(3000, result.feeMinor());
    assertEquals(1500, result.driverCompensationMinor());
    assertEquals(1500, result.platformAmountMinor());
    // Fee always splits exactly between the two -- the one invariant that
    // must hold for LedgerService's later posting to balance.
    assertEquals(result.feeMinor(), result.driverCompensationMinor() + result.platformAmountMinor());
  }

  @Test
  void midWindowFeeNeverGoesBelowTheConfiguredMinimum() {
    CancellationFinanceService svc = new CancellationFinanceService(db);
    UUID bookingId = UUID.randomUUID();
    // A tiny fare where 30% would compute well under the 500-minor floor.
    stubPolicyAndBooking(bookingId, UUID.randomUUID(), 100, "CASH");

    CancellationFinanceService.ChargeResult result = svc.cancellation(bookingId, 600);

    // 30% of 100 = 30, below the 500 floor -- but also capped at the fare
    // itself (fee=Math.min(fee,base)), so the floor can't exceed the ride's
    // own price either.
    assertEquals(100, result.feeMinor());
  }

  @Test
  void noShowFeeNeverExceedsTheConfiguredCap() {
    CancellationFinanceService svc = new CancellationFinanceService(db);
    UUID bookingId = UUID.randomUUID();
    // A large fare where 100% no-show fee would blow past the cap.
    stubPolicyAndBooking(bookingId, UUID.randomUUID(), 50000, "ONLINE");

    CancellationFinanceService.ChargeResult result = svc.noShow(bookingId);

    // no_show_fee_bps=10000 (100%) of 50000 = 50000, but no_show_cap_minor=5000.
    assertEquals(5000, result.feeMinor());
    // driver_share_no_show_bps=8000 (80%) of the capped 5000 = 4000.
    assertEquals(4000, result.driverCompensationMinor());
    assertEquals(1000, result.platformAmountMinor());
  }

  @Test
  void bookingWithNoSelectedDriverChargesNothing() {
    CancellationFinanceService svc = new CancellationFinanceService(db);
    UUID bookingId = UUID.randomUUID();
    when(db.queryForList(contains("cancellation_policy_versions"))).thenReturn(List.of(policy()));

    java.util.Map<String, Object> bookingRow = new java.util.HashMap<>();
    bookingRow.put("payment_method", "ONLINE");
    bookingRow.put("creator_user_id", UUID.randomUUID());
    bookingRow.put("selected_driver_id", null);
    bookingRow.put("driver_proposed_amount_minor", null);
    when(db.queryForList(contains("from scheduled_bookings sb left join booking_financial_snapshots"), any(Object[].class)))
        .thenReturn(List.of(bookingRow));

    // No driver was ever matched -- nothing to charge or compensate.
    CancellationFinanceService.ChargeResult result = svc.cancellation(bookingId, 10);

    assertEquals(0, result.feeMinor());
  }
}
