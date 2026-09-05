package com.veyra.payment;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * Deliberately scoped to the one scenario testable with high confidence
 * without either constructing a real, cryptographically-signed Stripe
 * webhook payload (Webhook.constructEvent does real HMAC signature
 * verification against the raw request body) or blindly mockStatic()-ing
 * Stripe SDK internals this environment can't verify against a real
 * Stripe test event. The webhook-secret-not-configured path is real,
 * safe, self-contained logic worth covering on its own; the full
 * signature-verified happy path is a legitimate remaining gap, stated
 * here rather than covered by a test built on unverifiable assumptions
 * about Stripe's exact SDK object graph.
 */
@ExtendWith(MockitoExtension.class)
class StripeWebhookControllerTest {

  @Mock JdbcTemplate db;

  @Test
  void webhookNotConfiguredReturnsServiceUnavailableWithoutAttemptingVerification() throws Exception {
    StripeWebhookController controller = new StripeWebhookController(db, "");

    ResponseEntity<Void> response = controller.webhook("{}", "t=1,v1=irrelevant");

    assertEquals(HttpStatus.SERVICE_UNAVAILABLE, response.getStatusCode());
    verifyNoInteractions(db);
  }

  @Test
  void blankWebhookSecretIsTreatedTheSameAsNullOrMissing() throws Exception {
    StripeWebhookController controller = new StripeWebhookController(db, "   ");

    ResponseEntity<Void> response = controller.webhook("{}", "t=1,v1=irrelevant");

    assertEquals(HttpStatus.SERVICE_UNAVAILABLE, response.getStatusCode());
  }
}
