package com.veyra.provider;

/** Transactional SMS (DEC-07: Twilio). Returns false when not sent. */
public interface SmsProvider {
  boolean send(String toE164, String body);

  boolean isConfigured();
}
