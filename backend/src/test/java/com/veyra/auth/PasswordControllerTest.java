package com.veyra.auth;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mail.MailException;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.util.List;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * Zero coverage existed for the forgot/reset password flow before this --
 * the one place in the whole app where a wrong response (revealing
 * whether an email exists, or failing to revoke existing sessions on a
 * successful reset) is a direct account-takeover-adjacent risk, not just
 * an inconvenience.
 */
@ExtendWith(MockitoExtension.class)
class PasswordControllerTest {

  @Mock JdbcTemplate db;
  @Mock JavaMailSender mail;
  @Mock PasswordEncoder enc;

  @Test
  void forgotPasswordForARealEmailCreatesATokenAndSendsMail() {
    PasswordController controller = new PasswordController(db, mail, enc);
    UUID userId = UUID.randomUUID();
    when(db.queryForList(eq("select id from users where email=?"), eq(UUID.class), any(Object[].class)))
        .thenReturn(List.of(userId));

    ResponseEntity<Void> response = controller.forgot(new PasswordController.Forgot("driver@example.com"));

    assertEquals(HttpStatus.ACCEPTED, response.getStatusCode());
    verify(db).update(contains("insert into password_reset_tokens"), eq(userId), anyString(), any());
    verify(mail).send(any(SimpleMailMessage.class));
  }

  @Test
  void forgotPasswordForAnUnknownEmailStillReturnsAcceptedWithoutCreatingAnything() {
    // The whole point: an attacker probing for valid emails must see the
    // exact same response either way. A 404-vs-202 difference here would
    // itself be the account-enumeration bug.
    PasswordController controller = new PasswordController(db, mail, enc);
    when(db.queryForList(eq("select id from users where email=?"), eq(UUID.class), any(Object[].class)))
        .thenReturn(List.of());

    ResponseEntity<Void> response = controller.forgot(new PasswordController.Forgot("nobody@example.com"));

    assertEquals(HttpStatus.ACCEPTED, response.getStatusCode());
    verify(db, never()).update(contains("insert into password_reset_tokens"), any(), any(), any());
    verifyNoInteractions(mail);
  }

  @Test
  void forgotPasswordStillReturnsAcceptedEvenIfMailSendingFails() {
    // A down SMTP server must never turn into a signal an attacker can use
    // to distinguish "email exists but mail failed" from "email doesn't
    // exist" -- the controller's own catch(Exception ignored) exists
    // specifically for this, verified here rather than just trusted.
    PasswordController controller = new PasswordController(db, mail, enc);
    when(db.queryForList(eq("select id from users where email=?"), eq(UUID.class), any(Object[].class)))
        .thenReturn(List.of(UUID.randomUUID()));
    doThrow(new MailException("smtp down") {}).when(mail).send(any(SimpleMailMessage.class));

    ResponseEntity<Void> response = controller.forgot(new PasswordController.Forgot("driver@example.com"));

    assertEquals(HttpStatus.ACCEPTED, response.getStatusCode());
  }

  @Test
  void resetRejectsAWeakPasswordBeforeEverTouchingTheTokenTable() {
    PasswordController controller = new PasswordController(db, mail, enc);

    ResponseEntity<Void> response = controller.reset(new PasswordController.Reset("some-token", "short"));

    assertEquals(HttpStatus.UNPROCESSABLE_ENTITY, response.getStatusCode());
    verifyNoInteractions(db);
  }

  @Test
  void resetRejectsAnExpiredOrConsumedOrUnknownToken() {
    PasswordController controller = new PasswordController(db, mail, enc);
    when(db.queryForList(contains("consumed_at is null and expires_at>now()"), eq(UUID.class), any(Object[].class)))
        .thenReturn(List.of());

    ResponseEntity<Void> response = controller.reset(new PasswordController.Reset("expired-token", "aStrongPassword1"));

    assertEquals(HttpStatus.BAD_REQUEST, response.getStatusCode());
    // Broad array-level matcher deliberately -- catches an update() call
    // with ANY number of arguments, not just one specific arity. The real
    // failure path has three different update() calls with different
    // argument counts (2, 1, 1); a narrower matcher here would silently
    // miss two of them.
    verify(db, never()).update(anyString(), any(Object[].class));
  }

  @Test
  void validResetUpdatesPasswordConsumesTokenAndRevokesAllExistingSessions() {
    PasswordController controller = new PasswordController(db, mail, enc);
    UUID tokenId = UUID.randomUUID();
    UUID userId = UUID.randomUUID();
    when(db.queryForList(contains("consumed_at is null and expires_at>now()"), eq(UUID.class), any(Object[].class)))
        .thenReturn(List.of(tokenId));
    when(db.queryForObject(eq("select user_id from password_reset_tokens where id=?"), eq(UUID.class), eq(tokenId)))
        .thenReturn(userId);
    when(enc.encode("aStrongPassword1")).thenReturn("hashed-password");

    ResponseEntity<Void> response = controller.reset(new PasswordController.Reset("valid-token", "aStrongPassword1"));

    assertEquals(HttpStatus.NO_CONTENT, response.getStatusCode());
    verify(db).update(contains("update users set password_hash=?"), eq("hashed-password"), eq(userId));
    verify(db).update(contains("update password_reset_tokens set consumed_at=now()"), eq(tokenId));
    // The real point of this test: resetting a password must invalidate
    // every existing session, not just leave a stolen account's old
    // sessions (potentially the attacker's own) still logged in.
    verify(db).update(contains("update user_sessions set revoked_at=now()"), eq(userId));
  }
}
