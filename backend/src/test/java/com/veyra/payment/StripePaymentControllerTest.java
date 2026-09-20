package com.veyra.payment;

import com.stripe.model.PaymentIntent;
import com.veyra.shared.ApiException;
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
 * Real money moving through a real third-party PSP -- zero coverage
 * existed before this. The idempotent-replay path is the single most
 * important behavior here: a duplicate request with the same
 * Idempotency-Key must never create a second PaymentIntent or a second
 * payment row, or a retried request (network blip, client retry logic)
 * could double-charge a real customer.
 */
@ExtendWith(MockitoExtension.class)
class StripePaymentControllerTest {

  @Mock JdbcTemplate db;
  @Mock StripePaymentService stripe;
  @Mock PaymentIntent paymentIntent;

  private final UUID userId = UUID.randomUUID();
  private final UUID bookingId = UUID.randomUUID();

  @BeforeEach
  void setUpSecurityContext() {
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(userId, null));
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  private StripePaymentController controller() {
    return new StripePaymentController(db, stripe);
  }

  private void stubPayableBooking(String paymentMethod, String status) {
    when(db.queryForList(contains("from scheduled_bookings sb join booking_financial_snapshots"), eq(bookingId)))
        .thenReturn(List.of(Map.of(
            "creator_user_id", userId,
            "payment_method", paymentMethod,
            "status", status,
            "customer_total_amount_minor", 11000L,
            "currency", "EUR")));
  }

  @Test
  void blankIdempotencyKeyRejectedBeforeTouchingTheDatabase() throws Exception {
    ApiException ex = assertThrows(ApiException.class, () -> controller().createIntent(bookingId, "  "));

    assertEquals("INVALID_IDEMPOTENCY_KEY", ex.code());
    verifyNoInteractions(db);
  }

  @Test
  void oversizedIdempotencyKeyRejected() throws Exception {
    String tooLong = "x".repeat(129);

    ApiException ex = assertThrows(ApiException.class, () -> controller().createIntent(bookingId, tooLong));

    assertEquals("INVALID_IDEMPOTENCY_KEY", ex.code());
  }

  @Test
  void unknownBookingRejected() throws Exception {
    when(db.queryForList(contains("from scheduled_bookings sb join booking_financial_snapshots"), eq(bookingId)))
        .thenReturn(List.of());

    ApiException ex = assertThrows(ApiException.class, () -> controller().createIntent(bookingId, "key-1"));

    assertEquals("BOOKING_NOT_FOUND", ex.code());
  }

  @Test
  void anotherUsersBookingRejected() throws Exception {
    when(db.queryForList(contains("from scheduled_bookings sb join booking_financial_snapshots"), eq(bookingId)))
        .thenReturn(List.of(Map.of(
            "creator_user_id", UUID.randomUUID(), // a different user
            "payment_method", "ONLINE",
            "status", "CONFIRMED",
            "customer_total_amount_minor", 11000L,
            "currency", "EUR")));

    ApiException ex = assertThrows(ApiException.class, () -> controller().createIntent(bookingId, "key-1"));

    assertEquals("FORBIDDEN", ex.code());
    verifyNoInteractions(stripe);
  }

  @Test
  void cashBookingRejectedAsNotPayableOnline() throws Exception {
    stubPayableBooking("CASH", "CONFIRMED");

    ApiException ex = assertThrows(ApiException.class, () -> controller().createIntent(bookingId, "key-1"));

    assertEquals("PAYMENT_METHOD_NOT_ONLINE", ex.code());
    verifyNoInteractions(stripe);
  }

  @Test
  void bookingInACompletedStateCannotBePaidAgain() throws Exception {
    stubPayableBooking("ONLINE", "COMPLETED");

    ApiException ex = assertThrows(ApiException.class, () -> controller().createIntent(bookingId, "key-1"));

    assertEquals("BOOKING_NOT_PAYABLE", ex.code());
  }

  @Test
  void replayingTheSameIdempotencyKeyNeverCreatesASecondPaymentIntent() throws Exception {
    stubPayableBooking("ONLINE", "CONFIRMED");
    when(db.queryForList(eq("select id,provider_payment_id,status,amount_minor,currency from payments where idempotency_key=?"), eq("key-1")))
        .thenReturn(List.of(Map.of(
            "id", UUID.randomUUID(),
            "provider_payment_id", "pi_existing",
            "status", "PENDING",
            "amount_minor", 11000L,
            "currency", "EUR")));
    when(stripe.retrieve("pi_existing")).thenReturn(paymentIntent);
    when(paymentIntent.getId()).thenReturn("pi_existing");
    when(paymentIntent.getClientSecret()).thenReturn("secret_existing");

    Map<String, Object> result = controller().createIntent(bookingId, "key-1");

    assertEquals("pi_existing", result.get("paymentIntentId"));
    // The real point of this test: no new PaymentIntent, no new payment row.
    verify(stripe, never()).create(anyLong(), anyString(), anyString(), anyString());
    verify(db, never()).update(anyString(), any(Object[].class));
  }

  @Test
  void freshRequestCreatesAPaymentIntentAndPersistsAPendingPayment() throws Exception {
    stubPayableBooking("ONLINE", "CONFIRMED");
    when(db.queryForList(eq("select id,provider_payment_id,status,amount_minor,currency from payments where idempotency_key=?"), eq("key-1")))
        .thenReturn(List.of());
    // Real gap this closes: the booking_id-scoped query added alongside
    // the ALREADY_PAID / resume-pending fix below is a SEPARATE
    // db.queryForList call from the idempotency_key one just above --
    // without stubbing it too, Mockito's default (null, not an empty
    // list) would make the controller's own .isEmpty() throw a
    // NullPointerException here, not the ApiException this test is
    // actually about. No prior payment for this booking at all is the
    // scenario under test, so an empty list is the correct stub.
    when(db.queryForList(eq("select id,provider_payment_id,status,amount_minor,currency from payments where booking_id=? order by created_at desc limit 1"), eq(bookingId)))
        .thenReturn(List.of());
    when(stripe.create(11000L, "EUR", bookingId.toString(), "key-1")).thenReturn(paymentIntent);
    when(paymentIntent.getId()).thenReturn("pi_new");
    when(paymentIntent.getClientSecret()).thenReturn("secret_new");

    Map<String, Object> result = controller().createIntent(bookingId, "key-1");

    assertEquals("pi_new", result.get("paymentIntentId"));
    assertEquals("PENDING", result.get("status"));
    assertEquals(11000L, result.get("amountMinor"));
    verify(db).update(contains("insert into payments"), any(), eq(bookingId), eq(userId), eq(11000L), eq("EUR"), eq("pi_new"), eq("key-1"));
  }

  @Test
  void aBookingThatIsAlreadyCapturedCannotBePaidAgainEvenWithADifferentIdempotencyKey() throws Exception {
    // The actual bug this whole fix targets: the client generates a
    // fresh idempotency key on every call
    // ('mobile-'+bookingId+'-'+timestamp), so the idempotency_key-only
    // check above could never catch a genuine retry in practice. This
    // is the scenario that mattered most -- a real retry, with a
    // different key, against a booking that was already paid for.
    stubPayableBooking("ONLINE", "CONFIRMED");
    when(db.queryForList(eq("select id,provider_payment_id,status,amount_minor,currency from payments where idempotency_key=?"), eq("key-2-a-different-key")))
        .thenReturn(List.of());
    when(db.queryForList(eq("select id,provider_payment_id,status,amount_minor,currency from payments where booking_id=? order by created_at desc limit 1"), eq(bookingId)))
        .thenReturn(List.of(Map.of(
            "id", UUID.randomUUID(),
            "provider_payment_id", "pi_already_captured",
            "status", "CAPTURED",
            "amount_minor", 11000L,
            "currency", "EUR")));

    ApiException ex = assertThrows(ApiException.class, () -> controller().createIntent(bookingId, "key-2-a-different-key"));

    assertEquals("ALREADY_PAID", ex.code());
    verifyNoInteractions(stripe);
  }

  @Test
  void aStillPendingPriorAttemptIsResumedInsteadOfStartingACompetingOne() throws Exception {
    // Same real-retry scenario, but the prior attempt's outcome isn't
    // known yet (still PENDING) rather than definitely settled. Must
    // hand back that SAME intent, matching what Stripe's own client SDK
    // expects (resume confirming the existing intent), rather than
    // create a second, independent one for the same charge.
    stubPayableBooking("ONLINE", "CONFIRMED");
    when(db.queryForList(eq("select id,provider_payment_id,status,amount_minor,currency from payments where idempotency_key=?"), eq("key-2-a-different-key")))
        .thenReturn(List.of());
    when(db.queryForList(eq("select id,provider_payment_id,status,amount_minor,currency from payments where booking_id=? order by created_at desc limit 1"), eq(bookingId)))
        .thenReturn(List.of(Map.of(
            "id", UUID.randomUUID(),
            "provider_payment_id", "pi_still_pending",
            "status", "PENDING",
            "amount_minor", 11000L,
            "currency", "EUR")));
    when(stripe.retrieve("pi_still_pending")).thenReturn(paymentIntent);
    when(paymentIntent.getId()).thenReturn("pi_still_pending");
    when(paymentIntent.getClientSecret()).thenReturn("secret_still_pending");

    Map<String, Object> result = controller().createIntent(bookingId, "key-2-a-different-key");

    assertEquals("pi_still_pending", result.get("paymentIntentId"));
    assertEquals("PENDING", result.get("status"));
    verify(stripe, never()).create(anyLong(), anyString(), anyString(), anyString());
    verify(db, never()).update(anyString(), any(Object[].class));
  }

  @Test
  void aPriorFailedAttemptDoesNotBlockATrulyFreshOne() throws Exception {
    // A declined card, for example, is genuinely dead -- the person
    // trying again (possibly with a different card) must be allowed to,
    // not permanently blocked because some earlier attempt exists.
    stubPayableBooking("ONLINE", "CONFIRMED");
    when(db.queryForList(eq("select id,provider_payment_id,status,amount_minor,currency from payments where idempotency_key=?"), eq("key-3")))
        .thenReturn(List.of());
    when(db.queryForList(eq("select id,provider_payment_id,status,amount_minor,currency from payments where booking_id=? order by created_at desc limit 1"), eq(bookingId)))
        .thenReturn(List.of(Map.of(
            "id", UUID.randomUUID(),
            "provider_payment_id", "pi_declined",
            "status", "FAILED",
            "amount_minor", 11000L,
            "currency", "EUR")));
    when(stripe.create(11000L, "EUR", bookingId.toString(), "key-3")).thenReturn(paymentIntent);
    when(paymentIntent.getId()).thenReturn("pi_fresh_attempt");
    when(paymentIntent.getClientSecret()).thenReturn("secret_fresh_attempt");

    Map<String, Object> result = controller().createIntent(bookingId, "key-3");

    assertEquals("pi_fresh_attempt", result.get("paymentIntentId"));
    verify(stripe).create(11000L, "EUR", bookingId.toString(), "key-3");
  }

  @Test
  void listingPaymentsForSomeoneElsesBookingIsForbidden() {
    when(db.queryForObject(anyString(), eq(Integer.class), eq(bookingId), eq(userId))).thenReturn(0);

    ApiException ex = assertThrows(ApiException.class, () -> controller().bookingPayments(bookingId));

    assertEquals("FORBIDDEN", ex.code());
  }
}
