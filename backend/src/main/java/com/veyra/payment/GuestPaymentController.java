package com.veyra.payment;

import com.stripe.model.PaymentIntent;
import com.veyra.shared.ApiException;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;

/**
 * Online payment by the passenger through the secure link (PART-10/13):
 * the link's token is the only credential; the reception never enters
 * the passenger's card. Also exposes the Stripe publishable key for the
 * web card form (public by design, configured on Render).
 */
@RestController
@RequestMapping("/api/v1/guest")
public class GuestPaymentController {
  static final java.util.regex.Pattern TOKEN = java.util.regex.Pattern.compile("[A-Za-z0-9_-]{43}");
  static final Set<String> PAYABLE = Set.of("CONFIRMED", "DRIVER_EN_ROUTE", "DRIVER_ARRIVED");

  private final JdbcTemplate db;
  private final StripePaymentService stripe;
  private final String publishableKey;

  public GuestPaymentController(JdbcTemplate db, StripePaymentService stripe, @Value("${veyra.stripe.publishable-key:}") String publishableKey) {
    this.db = db;
    this.stripe = stripe;
    this.publishableKey = publishableKey == null ? "" : publishableKey.trim();
  }

  @GetMapping("/payment-config")
  public Map<String, Object> config() {
    boolean enabled = stripe.isConfigured() && publishableKey.startsWith("pk_");
    return enabled ? Map.of("enabled", true, "publishableKey", publishableKey) : Map.of("enabled", false);
  }

  @PostMapping("/bookings/{token}/payment")
  @Transactional(rollbackFor = Exception.class)
  public Map<String, Object> pay(@PathVariable String token) throws Exception {
    if (!TOKEN.matcher(token).matches()) throw invalid();
    List<Map<String, Object>> rows = db.queryForList(
        "select sb.id,sb.status,sb.payment_method,sb.payer_type,bfs.customer_total_amount_minor,bfs.currency " +
        "from guest_access_links g join scheduled_bookings sb on sb.id=g.booking_id join booking_financial_snapshots bfs on bfs.booking_id=sb.id " +
        "where g.token_hash=? and g.revoked_at is null and g.expires_at>now() for update of sb", sha256(token));
    if (rows.isEmpty()) throw invalid();
    Map<String, Object> b = rows.getFirst();
    if (!"GUEST".equals(b.get("payer_type")) || !"ONLINE".equals(b.get("payment_method")))
      throw new ApiException(HttpStatus.CONFLICT, "PAYMENT_NOT_EXPECTED");
    if (!PAYABLE.contains(b.get("status"))) throw new ApiException(HttpStatus.CONFLICT, "BOOKING_NOT_PAYABLE");
    UUID booking = (UUID) b.get("id");
    long amount = ((Number) b.get("customer_total_amount_minor")).longValue();
    String currency = (String) b.get("currency");

    // One live intent per booking: resume it rather than start a second charge.
    List<Map<String, Object>> last = db.queryForList(
        "select id,provider_payment_id,status from payments where booking_id=? order by created_at desc limit 1", booking);
    String previous = last.isEmpty() ? "initial" : last.getFirst().get("id").toString();
    if (!last.isEmpty()) {
      Map<String, Object> p = last.getFirst();
      if ("CAPTURED".equals(p.get("status"))) throw new ApiException(HttpStatus.CONFLICT, "ALREADY_PAID");
      if (Set.of("PENDING", "FAILED").contains(p.get("status"))) {
        PaymentIntent pi = stripe.retrieve((String) p.get("provider_payment_id"));
        if ("succeeded".equals(pi.getStatus())) throw new ApiException(HttpStatus.CONFLICT, "ALREADY_PAID");
        if (!"canceled".equals(pi.getStatus())) return result(pi.getClientSecret(), amount, currency);
      }
    }
    PaymentIntent pi = stripe.create(amount, currency, booking.toString(), "guest-" + booking + "-after-" + previous);
    db.update("insert into payments(id,booking_id,payer_user_id,amount_minor,currency,method,status,provider,provider_payment_id,idempotency_key) " +
        "values (?,?,null,?,?,'ONLINE','PENDING','STRIPE',?,?)",
        UUID.randomUUID(), booking, amount, currency, pi.getId(), "guest-" + booking + "-" + UUID.randomUUID());
    return result(pi.getClientSecret(), amount, currency);
  }

  private Map<String, Object> result(String clientSecret, long amount, String currency) {
    Map<String, Object> out = new LinkedHashMap<>();
    out.put("clientSecret", clientSecret);
    out.put("amountMinor", amount);
    out.put("currency", currency);
    out.put("publishableKey", publishableKey);
    return out;
  }

  private static ApiException invalid() { return new ApiException(HttpStatus.NOT_FOUND, "GUEST_LINK_INVALID"); }

  static String sha256(String value) {
    try {
      return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8)));
    } catch (Exception e) {
      throw new IllegalStateException(e);
    }
  }
}
