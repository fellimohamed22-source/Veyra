package com.veyra.payment;

import com.stripe.model.PaymentIntent;
import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

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
  public Map<String, Object> createIntent(
      @PathVariable UUID bookingId,
      @RequestHeader("Idempotency-Key") String idempotencyKey) throws Exception {

    if (idempotencyKey == null || idempotencyKey.isBlank() || idempotencyKey.length() > 128) {
      throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_IDEMPOTENCY_KEY");
    }

    List<Map<String, Object>> rows = db.queryForList(
        "select sb.creator_user_id,sb.payment_method,sb.status,bfs.customer_total_amount_minor,bfs.currency " +
        "from scheduled_bookings sb join booking_financial_snapshots bfs on bfs.booking_id=sb.id where sb.id=?",
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
        "select id,provider_payment_id,status,amount_minor,currency from payments where idempotency_key=?",
        idempotencyKey);
    if (!existing.isEmpty()) {
      Map<String, Object> p = existing.getFirst();
      PaymentIntent pi = stripe.retrieve((String) p.get("provider_payment_id"));
      return Map.of(
          "paymentId", p.get("id"),
          "paymentIntentId", pi.getId(),
          "clientSecret", pi.getClientSecret(),
          "status", p.get("status"),
          "amountMinor", p.get("amount_minor"),
          "currency", p.get("currency"));
    }

    long amount = ((Number) booking.get("customer_total_amount_minor")).longValue();
    String currency = (String) booking.get("currency");
    PaymentIntent pi = stripe.create(amount, currency, bookingId.toString(), idempotencyKey);
    UUID paymentId = UUID.randomUUID();

    db.update(
        "insert into payments(id,booking_id,payer_user_id,amount_minor,currency,method,status,provider,provider_payment_id,idempotency_key) " +
        "values (?,?,?,?,?,'ONLINE','PENDING','STRIPE',?,?)",
        paymentId, bookingId, CurrentUser.id(), amount, currency, pi.getId(), idempotencyKey);

    return Map.of(
        "paymentId", paymentId,
        "paymentIntentId", pi.getId(),
        "clientSecret", pi.getClientSecret(),
        "status", "PENDING",
        "amountMinor", amount,
        "currency", currency);
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
