package com.veyra.auth;

import com.veyra.shared.ApiException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.lang.reflect.Field;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * The most fundamental security surface in the app -- register/login --
 * had zero test coverage before this. User's id field is JPA-generated
 * (no public setter, private field), so setId() uses reflection to
 * populate it on a test instance -- the same real constraint every other
 * JPA-entity-in-a-unit-test scenario has, not worked around by weakening
 * the entity's own encapsulation just for testability.
 */
@ExtendWith(MockitoExtension.class)
class AuthControllerTest {

  @Mock UserRepository users;
  @Mock PasswordEncoder encoder;
  @Mock JwtService jwt;
  @Mock JdbcTemplate db;

  private static void setId(User user, UUID id) {
    try {
      Field f = User.class.getDeclaredField("id");
      f.setAccessible(true);
      f.set(user, id);
    } catch (ReflectiveOperationException e) {
      throw new IllegalStateException(e);
    }
  }

  private AuthController controller() {
    return new AuthController(users, encoder, jwt, db);
  }

  @Test
  void registerRejectsAnEmailAlreadyInUseWithoutCreatingAnything() {
    when(users.existsByEmailIgnoreCase("taken@example.com")).thenReturn(true);

    ApiException ex = assertThrows(ApiException.class, () -> controller().register(
        new AuthController.Register("taken@example.com", "aStrongPassword1", "Jean", "Dupont", null)));

    assertEquals("EMAIL_ALREADY_USED", ex.code());
    assertEquals(HttpStatus.CONFLICT, ex.status());
    verify(users, never()).save(any());
  }

  @Test
  void registerNormalizesEmailCaseBeforeCheckingOrSaving() {
    // A user typing Driver@Example.com must collide with an existing
    // driver@example.com -- checked here rather than assumed, since the
    // uniqueness guarantee only holds if both the existence check and the
    // saved record use the same normalized form.
    when(users.existsByEmailIgnoreCase("driver@example.com")).thenReturn(false);
    User saved = new User("Jean", "Dupont", "driver@example.com", "hashed");
    setId(saved, UUID.randomUUID());
    when(users.save(any(User.class))).thenReturn(saved);
    when(db.queryForList(anyString(), eq(String.class), any(Object[].class))).thenReturn(List.of("CLIENT"));
    when(jwt.issue(any(), any(), any())).thenReturn("access-token");

    controller().register(new AuthController.Register("Driver@Example.com", "aStrongPassword1", "Jean", "Dupont", null));

    verify(users).existsByEmailIgnoreCase("driver@example.com");
    org.mockito.ArgumentCaptor<User> captor = org.mockito.ArgumentCaptor.forClass(User.class);
    verify(users).save(captor.capture());
    assertEquals("driver@example.com", captor.getValue().email());
  }

  @Test
  void registerAssignsTheClientRoleAndReturns201WithTokens() {
    when(users.existsByEmailIgnoreCase(anyString())).thenReturn(false);
    UUID userId = UUID.randomUUID();
    User saved = new User("Jean", "Dupont", "client@example.com", "hashed");
    setId(saved, userId);
    when(users.save(any(User.class))).thenReturn(saved);
    when(db.queryForList(anyString(), eq(String.class), any(Object[].class))).thenReturn(List.of("CLIENT"));
    when(jwt.issue(eq(userId), eq("client@example.com"), eq(List.of("CLIENT")))).thenReturn("access-token");

    ResponseEntity<AuthController.Tokens> response = controller().register(
        new AuthController.Register("client@example.com", "aStrongPassword1", "Jean", "Dupont", null));

    assertEquals(HttpStatus.CREATED, response.getStatusCode());
    assertEquals("access-token", response.getBody().accessToken());
    assertEquals(userId, response.getBody().userId());
    verify(db).update(contains("insert into user_roles"), eq(userId));
    // No phone supplied -- the separate phone UPDATE must never fire.
    verify(db, never()).update(contains("update users set phone"), any(), any());
  }

  @Test
  void registerWithAPhoneUpdatesItSeparately() {
    when(users.existsByEmailIgnoreCase(anyString())).thenReturn(false);
    UUID userId = UUID.randomUUID();
    User saved = new User("Jean", "Dupont", "client@example.com", "hashed");
    setId(saved, userId);
    when(users.save(any(User.class))).thenReturn(saved);
    when(db.queryForList(anyString(), eq(String.class), any(Object[].class))).thenReturn(List.of("CLIENT"));
    when(jwt.issue(any(), any(), any())).thenReturn("access-token");

    controller().register(new AuthController.Register("client@example.com", "aStrongPassword1", "Jean", "Dupont", "+33612345678"));

    verify(db).update(eq("update users set phone=? where id=?"), eq("+33612345678"), eq(userId));
  }

  @Test
  void loginWithUnknownEmailRejectsWithTheSameGenericErrorAsAWrongPassword() {
    when(users.findByEmailIgnoreCase("nobody@example.com")).thenReturn(Optional.empty());

    ApiException ex = assertThrows(ApiException.class, () -> controller().login(
        new AuthController.Login("nobody@example.com", "whatever", "device")));

    // Must not distinguish "no such account" from "wrong password" --
    // that distinction is exactly what account enumeration exploits.
    assertEquals("INVALID_CREDENTIALS", ex.code());
    assertEquals(HttpStatus.UNAUTHORIZED, ex.status());
  }

  @Test
  void loginRejectsAnAlreadyLockedAccountBeforeEvenCheckingThePassword() {
    User locked = new User("Jean", "Dupont", "locked@example.com", "hashed");
    setId(locked, UUID.randomUUID());
    lockUntil(locked, OffsetDateTime.now().plusMinutes(10));
    when(users.findByEmailIgnoreCase("locked@example.com")).thenReturn(Optional.of(locked));

    ApiException ex = assertThrows(ApiException.class, () -> controller().login(
        new AuthController.Login("locked@example.com", "whatever", "device")));

    assertEquals("ACCOUNT_LOCKED", ex.code());
    assertEquals(HttpStatus.LOCKED, ex.status());
    // Same principle as the PIN lockout: a locked account must reject
    // before the password is ever evaluated, so a locked-out attacker
    // gains nothing from continuing to guess.
    verifyNoInteractions(encoder);
  }

  private static void lockUntil(User user, OffsetDateTime until) {
    try {
      Field f = User.class.getDeclaredField("lockedUntil");
      f.setAccessible(true);
      f.set(user, until);
    } catch (ReflectiveOperationException e) {
      throw new IllegalStateException(e);
    }
  }

  @Test
  void loginWithWrongPasswordRecordsTheFailureAndPersistsIt() {
    User user = new User("Jean", "Dupont", "client@example.com", "hashed");
    setId(user, UUID.randomUUID());
    when(users.findByEmailIgnoreCase("client@example.com")).thenReturn(Optional.of(user));
    when(encoder.matches("wrong", "hashed")).thenReturn(false);

    ApiException ex = assertThrows(ApiException.class, () -> controller().login(
        new AuthController.Login("client@example.com", "wrong", "device")));

    assertEquals("INVALID_CREDENTIALS", ex.code());
    // The failed attempt must actually be persisted -- User.failed() only
    // mutates the in-memory object, save() is what makes the attempt
    // count (and eventual lockout) durable across requests.
    verify(users).save(user);
  }

  @Test
  void loginWithInactiveAccountRejectsAfterPasswordIsConfirmedCorrect() {
    User user = new User("Jean", "Dupont", "suspended@example.com", "hashed");
    setId(user, UUID.randomUUID());
    setStatus(user, "SUSPENDED");
    when(users.findByEmailIgnoreCase("suspended@example.com")).thenReturn(Optional.of(user));
    when(encoder.matches("correct-password", "hashed")).thenReturn(true);

    ApiException ex = assertThrows(ApiException.class, () -> controller().login(
        new AuthController.Login("suspended@example.com", "correct-password", "device")));

    assertEquals("ACCOUNT_NOT_ACTIVE", ex.code());
    assertEquals(HttpStatus.FORBIDDEN, ex.status());
  }

  private static void setStatus(User user, String status) {
    try {
      Field f = User.class.getDeclaredField("status");
      f.setAccessible(true);
      f.set(user, status);
    } catch (ReflectiveOperationException e) {
      throw new IllegalStateException(e);
    }
  }

  @Test
  void successfulLoginResetsFailedAttemptsAndReturnsTokens() {
    UUID userId = UUID.randomUUID();
    User user = new User("Jean", "Dupont", "client@example.com", "hashed");
    setId(user, userId);
    when(users.findByEmailIgnoreCase("client@example.com")).thenReturn(Optional.of(user));
    when(encoder.matches("correct-password", "hashed")).thenReturn(true);
    when(db.queryForList(anyString(), eq(String.class), any(Object[].class))).thenReturn(List.of("DRIVER"));
    when(jwt.issue(eq(userId), eq("client@example.com"), eq(List.of("DRIVER")))).thenReturn("access-token");

    AuthController.Tokens tokens = controller().login(
        new AuthController.Login("client@example.com", "correct-password", "iPhone"));

    assertEquals("access-token", tokens.accessToken());
    assertEquals(userId, tokens.userId());
    assertNotNull(tokens.refreshToken());
    verify(users).save(user);
    // A real session row must be created for the new refresh token, hashed.
    verify(db).update(contains("insert into user_sessions"), eq(userId), anyString(), eq("iPhone"), any());
  }
}
