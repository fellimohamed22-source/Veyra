package com.veyra.payment;

import com.stripe.exception.SignatureVerificationException;
import com.stripe.model.Event;
import com.stripe.model.PaymentIntent;
import com.stripe.net.Webhook;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/payments/stripe")
public class StripeWebhookController {
  private final JdbcTemplate db;
  private final String webhookSecret;

  public StripeWebhookController(
      JdbcTemplate db,
      @Value("${veyra.stripe.webhook-secret:}") String webhookSecret) {
    this.db = db;
    this.webhookSecret = webhookSecret == null ? "" : webhookSecret.trim();
  }

  @PostMapping("/webhook")
  public ResponseEntity<Void> webhook(
      @RequestBody String payload,
      @RequestHeader("Stripe-Signature") String signature) throws Exception {

    if (webhookSecret.isBlank()) {
      return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).build();
    }

    Event event;
    try {
      event = Webhook.constructEvent(payload, signature, webhookSecret);
    } catch (SignatureVerificationException e) {
      return ResponseEntity.badRequest().build();
    }
    Object object = event.getDataObjectDeserializer().getObject().orElse(null);

    if (object instanceof PaymentIntent paymentIntent) {
      String status = switch (event.getType()) {
        case "payment_intent.succeeded" -> "CAPTURED";
        case "payment_intent.payment_failed" -> "FAILED";
        case "payment_intent.canceled" -> "CANCELED";
        default -> null;
      };
      if (status != null) {
        db.update(
            "update payments set status=? where provider='STRIPE' and provider_payment_id=?",
            status,
            paymentIntent.getId());
      }
    }

    return ResponseEntity.ok().build();
  }
}
