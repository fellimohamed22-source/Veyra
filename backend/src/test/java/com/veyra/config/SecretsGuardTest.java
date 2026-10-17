package com.veyra.config;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class SecretsGuardTest {
  static final String DEV_JWT="dev-only-change-this-secret-at-least-32-bytes";
  static final String DEV_PIN="dev-pin-key-must-be-32-bytes-long";

  @Test
  void publicDevelopmentDefaultsAreRefusedUnlessExplicitlyAllowed(){
    assertThrows(IllegalStateException.class,()->SecretsGuard.check(DEV_JWT,"a-real-pin-key-of-at-least-32-bytes!!",false));
    assertThrows(IllegalStateException.class,()->SecretsGuard.check("a-real-jwt-secret-of-at-least-32-bytes",DEV_PIN,false));
    assertDoesNotThrow(()->SecretsGuard.check(DEV_JWT,DEV_PIN,true));
  }

  @Test
  void identicalJwtAndPinSecretsAreRefused(){
    String same="the-same-secret-reused-for-both-purposes";
    assertThrows(IllegalStateException.class,()->SecretsGuard.check(same,same,false));
  }

  @Test
  void distinctRealSecretsAreAccepted(){
    assertDoesNotThrow(()->SecretsGuard.check("a-real-jwt-secret-of-at-least-32-bytes","a-real-pin-key-of-at-least-32-bytes!!",false));
  }
}
