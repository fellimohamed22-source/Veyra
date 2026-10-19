package com.veyra.payment;

import com.stripe.model.PaymentIntent;
import com.veyra.shared.ApiException;
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
import static org.mockito.Mockito.*;

/** Passenger payment through the secure link (PART-10): the token is the only credential. */
@ExtendWith(MockitoExtension.class)
class GuestPaymentControllerTest {
  @Mock JdbcTemplate db;
  @Mock StripePaymentService stripe;
  @Mock PaymentIntent intent;

  final String token = "A".repeat(43);
  final UUID booking = UUID.randomUUID();

  GuestPaymentController controller() { return new GuestPaymentController(db, stripe, "pk_test_public"); }

  void stubBooking(String payer, String status) {
    when(db.queryForList(contains("from guest_access_links g"), eq(GuestPaymentController.sha256(token))))
        .thenReturn(List.of(Map.of("id", booking, "status", status, "payment_method", "ONLINE", "payer_type", payer,
            "customer_total_amount_minor", 5280L, "currency", "EUR")));
  }

  @Test void malformedOrUnknownTokenIsRejected() {
    assertEquals("GUEST_LINK_INVALID", assertThrows(ApiException.class, () -> controller().pay("short")).code());
    when(db.queryForList(contains("from guest_access_links g"), anyString())).thenReturn(List.of());
    assertEquals("GUEST_LINK_INVALID", assertThrows(ApiException.class, () -> controller().pay(token)).code());
    verifyNoInteractions(stripe);
  }

  @Test void establishmentPaidBookingIsNotPayableFromTheLink() {
    stubBooking("PARTNER", "CONFIRMED");
    assertEquals("PAYMENT_NOT_EXPECTED", assertThrows(ApiException.class, () -> controller().pay(token)).code());
  }

  @Test void bookingWithoutADriverYetCannotBePaid() {
    stubBooking("GUEST", "OFFERS_RECEIVED");
    assertEquals("BOOKING_NOT_PAYABLE", assertThrows(ApiException.class, () -> controller().pay(token)).code());
  }

  @Test void alreadyPaidIsRefused() {
    stubBooking("GUEST", "CONFIRMED");
    when(db.queryForList(contains("from payments where booking_id=?"), eq(booking)))
        .thenReturn(List.of(Map.of("id", UUID.randomUUID(), "provider_payment_id", "pi_1", "status", "CAPTURED")));
    assertEquals("ALREADY_PAID", assertThrows(ApiException.class, () -> controller().pay(token)).code());
    verifyNoInteractions(stripe);
  }

  @Test void freshPaymentCreatesOneIntentWithoutPayerAccount() throws Exception {
    stubBooking("GUEST", "CONFIRMED");
    when(db.queryForList(contains("from payments where booking_id=?"), eq(booking))).thenReturn(List.of());
    when(stripe.create(eq(5280L), eq("EUR"), eq(booking.toString()), eq("guest-" + booking + "-after-initial"))).thenReturn(intent);
    when(intent.getId()).thenReturn("pi_guest");
    when(intent.getClientSecret()).thenReturn("secret_guest");

    Map<String, Object> r = controller().pay(token);

    assertEquals("secret_guest", r.get("clientSecret"));
    assertEquals("pk_test_public", r.get("publishableKey"));
    verify(db).update(contains("values (?,?,null,?,?,'ONLINE','PENDING','STRIPE',?,?)"), any(), eq(booking), eq(5280L), eq("EUR"), eq("pi_guest"), anyString());
  }

  @Test void configIsDisabledWithoutKeys() {
    when(stripe.isConfigured()).thenReturn(false);
    assertEquals(false, controller().config().get("enabled"));
    assertNull(controller().config().get("publishableKey"));
  }
}
