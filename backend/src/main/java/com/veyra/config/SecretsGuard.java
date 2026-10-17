package com.veyra.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.util.Set;

/**
 * Refuses to start with the development defaults of application.yml.
 * Those values are public (the repository is public), so a deployment
 * that forgot JWT_SECRET would accept forged tokens for any user id,
 * admins included. Local development opts in explicitly with
 * VEYRA_ALLOW_DEV_SECRETS=true.
 */
@Component
public class SecretsGuard {
  static final Set<String> KNOWN_DEV_VALUES=Set.of(
      "dev-only-change-this-secret-at-least-32-bytes",
      "dev-pin-key-must-be-32-bytes-long");

  public SecretsGuard(
      @Value("${veyra.jwt.secret}") String jwtSecret,
      @Value("${veyra.crypto.pin-key}") String pinKey,
      @Value("${veyra.security.allow-dev-secrets:false}") boolean allowDevSecrets){
    check(jwtSecret,pinKey,allowDevSecrets);
  }

  static void check(String jwtSecret,String pinKey,boolean allowDevSecrets){
    if(allowDevSecrets)return;
    if(KNOWN_DEV_VALUES.contains(jwtSecret))
      throw new IllegalStateException("JWT_SECRET is not set: refusing to start with the public development default");
    if(KNOWN_DEV_VALUES.contains(pinKey))
      throw new IllegalStateException("PIN_ENCRYPTION_KEY is not set: refusing to start with the public development default");
    if(jwtSecret.equals(pinKey))
      throw new IllegalStateException("JWT_SECRET and PIN_ENCRYPTION_KEY must be distinct secrets");
  }
}
