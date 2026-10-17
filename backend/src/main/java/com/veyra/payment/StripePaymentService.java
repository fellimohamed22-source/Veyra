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
    return create(amountMinor,currency,bookingId,idempotencyKey,null);
  }

  /**
   * DEC-04: charge at booking confirmation. With a customer, the card the
   * client enters is saved on their Stripe customer (setup_future_usage)
   * and offered again by the PaymentSheet on the next booking.
   */
  public PaymentIntent create(
      long amountMinor,
      String currency,
      String bookingId,
      String idempotencyKey,
      String customerId) throws Exception {
    configure();
    PaymentIntentCreateParams.Builder params = PaymentIntentCreateParams.builder()
        .setAmount(amountMinor)
        .setCurrency(currency.toLowerCase())
        .putMetadata("bookingId", bookingId)
        .setAutomaticPaymentMethods(
            PaymentIntentCreateParams.AutomaticPaymentMethods.builder()
                .setEnabled(true)
                .build());
    if (customerId != null) {
      params.setCustomer(customerId)
          .setSetupFutureUsage(PaymentIntentCreateParams.SetupFutureUsage.OFF_SESSION);
    }
    RequestOptions options = RequestOptions.builder()
        .setIdempotencyKey(idempotencyKey)
        .build();
    return PaymentIntent.create(params.build(), options);
  }

  /** Creates the Stripe customer of a VEYRA user (idempotent per user). */
  public String createCustomer(String userId, String email) throws Exception {
    configure();
    var params = com.stripe.param.CustomerCreateParams.builder()
        .setEmail(email)
        .putMetadata("veyraUserId", userId)
        .build();
    var options = RequestOptions.builder().setIdempotencyKey("customer-" + userId).build();
    return com.stripe.model.Customer.create(params, options).getId();
  }

  /** Short-lived key letting the mobile PaymentSheet list and save the customer's cards. */
  public String ephemeralKey(String customerId) throws Exception {
    configure();
    var params = com.stripe.param.EphemeralKeyCreateParams.builder()
        .setCustomer(customerId)
        .setStripeVersion(Stripe.API_VERSION)
        .build();
    return com.stripe.model.EphemeralKey.create(params).getSecret();
  }

  /** Saved cards: brand, last 4 digits and expiry only (no card number ever reaches VEYRA). */
  public java.util.List<java.util.Map<String, Object>> savedCards(String customerId) throws Exception {
    configure();
    var params = com.stripe.param.CustomerListPaymentMethodsParams.builder()
        .setType(com.stripe.param.CustomerListPaymentMethodsParams.Type.CARD)
        .build();
    var result = new java.util.ArrayList<java.util.Map<String, Object>>();
    for (var pm : com.stripe.model.Customer.retrieve(customerId).listPaymentMethods(params).getData()) {
      var card = pm.getCard();
      var row = new java.util.LinkedHashMap<String, Object>();
      row.put("id", pm.getId());
      row.put("brand", card == null ? null : card.getBrand());
      row.put("last4", card == null ? null : card.getLast4());
      row.put("expMonth", card == null ? null : card.getExpMonth());
      row.put("expYear", card == null ? null : card.getExpYear());
      result.add(row);
    }
    return result;
  }

  /** Removes a saved card, only if it belongs to this customer. */
  public void detachCard(String customerId, String paymentMethodId) throws Exception {
    configure();
    var pm = com.stripe.model.PaymentMethod.retrieve(paymentMethodId);
    if (!customerId.equals(pm.getCustomer())) {
      throw new ApiException(HttpStatus.NOT_FOUND, "PAYMENT_METHOD_NOT_FOUND");
    }
    pm.detach();
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
