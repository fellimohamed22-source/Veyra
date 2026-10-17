package com.veyra.payment;

import com.stripe.model.PaymentIntent;
import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;
import org.springframework.transaction.annotation.Transactional;

import java.util.*;

@RestController
@RequestMapping("/api/v1/payments")
public class StripePaymentController {
  private final JdbcTemplate db;
  private final StripePaymentService stripe;

  public StripePaymentController(JdbcTemplate db, StripePaymentService stripe) {
    this.db = db;
    this.stripe = stripe;
  }

  @PostMapping("/bookings/{bookingId}/intent")
  @Transactional(rollbackFor=Exception.class)
  public Map<String, Object> createIntent(
      @PathVariable UUID bookingId,
      @RequestHeader("Idempotency-Key") String idempotencyKey) throws Exception {

    if (idempotencyKey == null || idempotencyKey.isBlank() || idempotencyKey.length() > 128) {
      throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_IDEMPOTENCY_KEY");
    }

    List<Map<String, Object>> rows = db.queryForList(
        "select sb.creator_user_id,sb.payment_method,sb.status,bfs.customer_total_amount_minor,bfs.currency " +
        "from scheduled_bookings sb join booking_financial_snapshots bfs on bfs.booking_id=sb.id where sb.id=? for update of sb",
        bookingId);
    if (rows.isEmpty()) {
      throw new ApiException(HttpStatus.NOT_FOUND, "BOOKING_NOT_FOUND");
    }

    Map<String, Object> booking = rows.getFirst();
    if (!CurrentUser.id().equals(booking.get("creator_user_id"))) {
      throw new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN");
    }
    if (!"ONLINE".equals(booking.get("payment_method"))) {
      throw new ApiException(HttpStatus.CONFLICT, "PAYMENT_METHOD_NOT_ONLINE");
    }
    if (!Set.of("CONFIRMED", "DRIVER_EN_ROUTE", "DRIVER_ARRIVED").contains(booking.get("status"))) {
      throw new ApiException(HttpStatus.CONFLICT, "BOOKING_NOT_PAYABLE");
    }

    List<Map<String, Object>> existing = db.queryForList(
        "select id,booking_id,payer_user_id,provider_payment_id,status,amount_minor,currency from payments where idempotency_key=?",
        idempotencyKey);
    if (!existing.isEmpty()) {
      Map<String, Object> p = existing.getFirst();
      if(!bookingId.equals(p.get("booking_id")) || !CurrentUser.id().equals(p.get("payer_user_id")))
        throw new ApiException(HttpStatus.CONFLICT,"IDEMPOTENCY_KEY_CONFLICT");
      if("CAPTURED".equals(p.get("status")))throw new ApiException(HttpStatus.CONFLICT,"ALREADY_PAID");
      PaymentIntent pi = stripe.retrieve((String) p.get("provider_payment_id"));
      if("succeeded".equals(pi.getStatus()))throw new ApiException(HttpStatus.CONFLICT,"ALREADY_PAID");
      if("canceled".equals(pi.getStatus()))throw new ApiException(HttpStatus.CONFLICT,"PAYMENT_CANCELED");
      return withCustomer(Map.of(
          "paymentId", p.get("id"),
          "paymentIntentId", pi.getId(),
          "clientSecret", pi.getClientSecret(),
          "status", p.get("status"),
          "amountMinor", p.get("amount_minor"),
          "currency", p.get("currency")));
    }

    // Real bug fixed here, found during a UX/business audit (no crash,
    // no failing test -- only visible by reading what actually happens
    // on a retry): the check just above only catches a retry that
    // reuses the EXACT SAME idempotency key. The mobile client
    // generates a fresh key on every single call to this endpoint
    // ('mobile-'+bookingId+'-'+DateTime.now().microsecondsSinceEpoch),
    // so that check could never actually fire in practice -- a genuine
    // retry (app closed mid-flow, a network drop right after Stripe
    // itself already captured the charge but before the app received
    // confirmation, or simply tapping "Payer maintenant" twice) would
    // always look like a brand new payment attempt to this endpoint,
    // creating a second, independent Stripe PaymentIntent for the same
    // booking. Checking by booking_id instead of only idempotency_key
    // catches every one of those cases regardless of what key the
    // client happens to send.
    List<Map<String, Object>> byBooking = db.queryForList(
        "select id,provider_payment_id,status,amount_minor,currency from payments " +
        "where booking_id=? order by created_at desc limit 1",
        bookingId);
    if (!byBooking.isEmpty()) {
      Map<String, Object> p = byBooking.getFirst();
      String priorStatus = (String) p.get("status");
      if ("CAPTURED".equals(priorStatus)) {
        // Already paid for real -- never let a stale client screen
        // hand the payment sheet a fresh intent for a booking that is
        // already settled, which would risk a genuine second charge if
        // the person actually completes it.
        throw new ApiException(HttpStatus.CONFLICT, "ALREADY_PAID");
      }
      if ("PENDING".equals(priorStatus) || "FAILED".equals(priorStatus)) {
        // A prior attempt is still live (awaiting confirmation, or its
        // outcome simply isn't known yet). Hand back that SAME
        // PaymentIntent rather than starting a competing one -- this is
        // also exactly what Stripe's own client SDK expects: resume
        // confirming the existing intent, don't create a second one
        // for the same charge.
        PaymentIntent pi = stripe.retrieve((String) p.get("provider_payment_id"));
        if("succeeded".equals(pi.getStatus()))throw new ApiException(HttpStatus.CONFLICT,"ALREADY_PAID");
        if(!"canceled".equals(pi.getStatus())){
        return withCustomer(Map.of(
            "paymentId", p.get("id"),
            "paymentIntentId", pi.getId(),
            "clientSecret", pi.getClientSecret(),
            "status", priorStatus,
            "amountMinor", p.get("amount_minor"),
            "currency", p.get("currency")));
        }
      }
      // Only a canceled intent cannot be retried. A declined card leaves
      // the intent reusable with a different payment method.
    }

    long amount = ((Number) booking.get("customer_total_amount_minor")).longValue();
    String currency = (String) booking.get("currency");
    PaymentIntent pi = stripe.create(amount, currency, bookingId.toString(), "booking-"+bookingId+"-after-"+(byBooking.isEmpty()?"initial":byBooking.getFirst().get("id")), customerId());
    UUID paymentId = UUID.randomUUID();

    db.update(
        "insert into payments(id,booking_id,payer_user_id,amount_minor,currency,method,status,provider,provider_payment_id,idempotency_key) " +
        "values (?,?,?,?,?,'ONLINE','PENDING','STRIPE',?,?)",
        paymentId, bookingId, CurrentUser.id(), amount, currency, pi.getId(), idempotencyKey);

    return withCustomer(Map.of(
        "paymentId", paymentId,
        "paymentIntentId", pi.getId(),
        "clientSecret", pi.getClientSecret(),
        "status", "PENDING",
        "amountMinor", amount,
        "currency", currency));
  }

  /**
   * DEC-04: Stripe customer of the current user, created on first use.
   * Returns null when the PSP does not return one (e.g. tests), in which
   * case the payment still works but the card is not saved.
   */
  String customerId() throws Exception {
    UUID user = CurrentUser.id();
    List<String> known = db.queryForList(
        "select provider_customer_id from payment_customers where user_id=? and provider='STRIPE'", String.class, user);
    if (!known.isEmpty()) return known.getFirst();
    List<String> email = db.queryForList("select email::text from users where id=?", String.class, user);
    String created = stripe.createCustomer(user.toString(), email.isEmpty() ? null : email.getFirst());
    if (created == null) return null;
    db.update("insert into payment_customers(user_id,provider,provider_customer_id) values (?,'STRIPE',?) on conflict (user_id) do nothing",
        user, created);
    return db.queryForObject("select provider_customer_id from payment_customers where user_id=?", String.class, user);
  }

  /** Adds what the PaymentSheet needs to list and save the user's cards. */
  private Map<String, Object> withCustomer(Map<String, Object> intent) throws Exception {
    Map<String, Object> result = new LinkedHashMap<>(intent);
    String customer = customerId();
    if (customer != null) {
      result.put("customerId", customer);
      String key = stripe.ephemeralKey(customer);
      if (key != null) result.put("ephemeralKey", key);
    }
    return result;
  }

  /** Saved cards of the current user (brand, last 4, expiry). */
  @GetMapping("/methods")
  public List<Map<String, Object>> savedCards() throws Exception {
    List<String> known = db.queryForList(
        "select provider_customer_id from payment_customers where user_id=? and provider='STRIPE'", String.class, CurrentUser.id());
    if (known.isEmpty()) return List.of();
    return stripe.savedCards(known.getFirst());
  }

  @DeleteMapping("/methods/{paymentMethodId}")
  public void removeCard(@PathVariable String paymentMethodId) throws Exception {
    if (!paymentMethodId.matches("pm_[A-Za-z0-9]{1,100}")) throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_PAYMENT_METHOD");
    List<String> known = db.queryForList(
        "select provider_customer_id from payment_customers where user_id=? and provider='STRIPE'", String.class, CurrentUser.id());
    if (known.isEmpty()) throw new ApiException(HttpStatus.NOT_FOUND, "PAYMENT_METHOD_NOT_FOUND");
    stripe.detachCard(known.getFirst(), paymentMethodId);
  }

  @GetMapping("/bookings/{bookingId}")
  public List<Map<String, Object>> bookingPayments(@PathVariable UUID bookingId) {
    Integer allowed = db.queryForObject(
        "select count(*) from scheduled_bookings where id=? and creator_user_id=?",
        Integer.class, bookingId, CurrentUser.id());
    if (allowed == null || allowed == 0) {
      throw new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN");
    }
    return db.queryForList(
        "select id,amount_minor,currency,method,status,provider,provider_payment_id,created_at " +
        "from payments where booking_id=? order by created_at desc",
        bookingId);
  }
}
