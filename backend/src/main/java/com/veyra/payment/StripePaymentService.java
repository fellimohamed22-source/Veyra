package com.veyra.payment;

import com.stripe.Stripe;
import com.stripe.model.PaymentIntent;
import com.stripe.net.RequestOptions;
import com.stripe.param.PaymentIntentCreateParams;
import com.veyra.shared.ApiException;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

@Service
public class StripePaymentService {
  private final String secretKey;

  public StripePaymentService(@Value("${veyra.stripe.secret-key:}") String secretKey) {
    this.secretKey = secretKey == null ? "" : secretKey.trim();
  }

  public boolean isConfigured(){ return !secretKey.isBlank(); }

  private void configure() {
    if (secretKey.isBlank()) {
      throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "STRIPE_NOT_CONFIGURED");
    }
    Stripe.apiKey = secretKey;
  }

  public PaymentIntent create(
      long amountMinor,
      String currency,
      String bookingId,
      String idempotencyKey) throws Exception {
    configure();
    PaymentIntentCreateParams params = PaymentIntentCreateParams.builder()
        .setAmount(amountMinor)
        .setCurrency(currency.toLowerCase())
        .putMetadata("bookingId", bookingId)
        .setAutomaticPaymentMethods(
            PaymentIntentCreateParams.AutomaticPaymentMethods.builder()
                .setEnabled(true)
                .build())
        .build();
    RequestOptions options = RequestOptions.builder()
        .setIdempotencyKey(idempotencyKey)
        .build();
    return PaymentIntent.create(params, options);
  }

  public PaymentIntent retrieve(String paymentIntentId) throws Exception {
    configure();
    return PaymentIntent.retrieve(paymentIntentId);
  }

  public com.stripe.model.Refund refund(
      String paymentIntentId,
      long amountMinor,
      String idempotencyKey) throws Exception {
    configure();
    var params=com.stripe.param.RefundCreateParams.builder()
        .setPaymentIntent(paymentIntentId)
        .setAmount(amountMinor)
        .build();
    var options=RequestOptions.builder()
        .setIdempotencyKey(idempotencyKey)
        .build();
    return com.stripe.model.Refund.create(params,options);
  }
}
