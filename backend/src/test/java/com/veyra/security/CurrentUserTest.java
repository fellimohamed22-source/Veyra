package com.veyra.security;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;

class CurrentUserTest {

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  @Test
  void hasRoleMatchesTheRolePrefixConventionUsedByJwtFilter() {
    SecurityContextHolder.getContext().setAuthentication(
        new TestingAuthenticationToken(UUID.randomUUID(), null, "ROLE_ADMIN"));

    assertTrue(CurrentUser.hasRole("ADMIN"));
    assertFalse(CurrentUser.hasRole("SUPPORT"));
    assertFalse(CurrentUser.hasRole("DRIVER"));
  }

  @Test
  void hasRoleIsFalseWithNoMatchingAuthority() {
    SecurityContextHolder.getContext().setAuthentication(
        new TestingAuthenticationToken(UUID.randomUUID(), null, "ROLE_CLIENT"));

    assertFalse(CurrentUser.hasRole("ADMIN"));
  }

  @Test
  void idStillReturnsThePrincipalUnaffectedByTheNewMethod() {
    UUID userId = UUID.randomUUID();
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(userId, null));

    assertEquals(userId, CurrentUser.id());
  }
}
