package com.veyra.finance;

import com.veyra.shared.ApiException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.jdbc.core.JdbcTemplate;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * Real invoice-generation logic (period validation, account state
 * gating, aggregation of two different item types, total summation, due
 * date calculation) had zero coverage before this -- a bug here either
 * bills a partner incorrectly or silently invoices a partner whose
 * credit was never actually approved.
 */
@ExtendWith(MockitoExtension.class)
class PartnerInvoiceControllerTest {

  @Mock JdbcTemplate db;

  private final UUID partnerId = UUID.randomUUID();
  private final LocalDate from = LocalDate.of(2026, 1, 1);
  private final LocalDate to = LocalDate.of(2026, 1, 31);

  private PartnerInvoiceController controller() {
    return new PartnerInvoiceController(db);
  }

  @Test
  void periodEndingBeforeItStartsIsRejected() {
    ApiException ex = assertThrows(ApiException.class,
        () -> controller().generate(partnerId, to, from)); // swapped -- to before from

    assertEquals("INVALID_INVOICE_PERIOD", ex.code());
    verifyNoInteractions(db);
  }

  @Test
  void missingInvoiceAccountRejected() {
    when(db.queryForList(contains("from partner_organizations po join partner_invoice_accounts"), eq(partnerId)))
        .thenReturn(List.of());

    ApiException ex = assertThrows(ApiException.class, () -> controller().generate(partnerId, from, to));

    assertEquals("PARTNER_INVOICE_ACCOUNT_NOT_FOUND", ex.code());
  }

  @Test
  void accountWithUnapprovedCreditCannotBeInvoiced() {
    // status/invoice_status are fine, but credit_status is still PENDING --
    // all three real gates must hold, not just two out of three.
    when(db.queryForList(contains("from partner_organizations po join partner_invoice_accounts"), eq(partnerId)))
        .thenReturn(List.of(Map.of(
            "status", "APPROVED", "credit_status", "PENDING", "currency", "EUR",
            "payment_terms_days", 30, "invoice_status", "ACTIVE")));

    ApiException ex = assertThrows(ApiException.class, () -> controller().generate(partnerId, from, to));

    assertEquals("PARTNER_INVOICE_ACCOUNT_NOT_ACTIVE", ex.code());
  }

  private void stubActiveAccount() {
    when(db.queryForList(contains("from partner_organizations po join partner_invoice_accounts"), eq(partnerId)))
        .thenReturn(List.of(Map.of(
            "status", "APPROVED", "credit_status", "APPROVED", "currency", "EUR",
            "payment_terms_days", 30, "invoice_status", "ACTIVE")));
  }

  @Test
  void aPeriodWithNoBillableItemsAtAllIsRejected() {
    stubActiveAccount();
    when(db.queryForList(contains("'RIDE' as item_type"), eq(partnerId), eq(from), eq(to))).thenReturn(List.of());
    when(db.queryForList(contains("'CANCELLATION' as item_type"), eq(partnerId), eq(from), eq(to))).thenReturn(List.of());

    ApiException ex = assertThrows(ApiException.class, () -> controller().generate(partnerId, from, to));

    assertEquals("NO_INVOICE_ITEMS", ex.code());
  }

  @Test
  void generatingAnInvoiceSumsBothRideAndCancellationItemsCorrectly() {
    stubActiveAccount();
    UUID rideBookingId = UUID.randomUUID();
    UUID cancelledBookingId = UUID.randomUUID();
    when(db.queryForList(contains("'RIDE' as item_type"), eq(partnerId), eq(from), eq(to))).thenReturn(List.of(Map.of(
        "booking_id", rideBookingId, "driver_net_minor", 8000L, "commission_minor", 800L,
        "tax_minor", 0L, "total_minor", 8800L, "currency", "EUR")));
    when(db.queryForList(contains("'CANCELLATION' as item_type"), eq(partnerId), eq(from), eq(to))).thenReturn(List.of(Map.of(
        "booking_id", cancelledBookingId, "driver_net_minor", 1500L, "commission_minor", 500L,
        "tax_minor", 0L, "total_minor", 2000L, "currency", "EUR")));

    Map<String, Object> result = controller().generate(partnerId, from, to);

    // 8800 (ride) + 2000 (cancellation fee) = 10800 -- both item types
    // must actually be summed together, not just one or the other.
    assertEquals(10800L, result.get("totalMinor"));
    assertEquals(2, result.get("items"));
    assertEquals("ISSUED", result.get("status"));
    // payment_terms_days=30 -- the invoice is due 30 days after the
    // period's own end date, not 30 days from today.
    assertEquals(to.plusDays(30), result.get("dueAt"));

    verify(db).update(contains("insert into partner_invoices"), any(), eq(partnerId), eq(from), eq(to), eq(10800L), eq("EUR"), eq(to.plusDays(30)));
    verify(db, times(2)).update(contains("insert into partner_invoice_items"), any(), any(), any(), any(), any(), any());
    verify(db).update(contains("outstanding_minor=outstanding_minor+?"), eq(10800L), eq(partnerId));
  }

  @Test
  void listingInvoicesReturnsThemForTheRequestedPartner() {
    when(db.queryForList(contains("from partner_invoices where partner_id=?"), eq(partnerId)))
        .thenReturn(List.of(Map.of("id", UUID.randomUUID(), "status", "ISSUED")));

    List<Map<String, Object>> invoices = controller().invoices(partnerId);

    assertEquals(1, invoices.size());
  }
}
