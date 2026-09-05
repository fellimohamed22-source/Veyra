package com.veyra.auth;

import com.veyra.shared.ApiException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * Refresh token rotation had zero coverage before this -- explicitly
 * required by the MVP spec's own test list (section 76.8: "Refresh token
 * reused after rotation -> rejected"). A bug here either lets a stolen
 * refresh token be replayed indefinitely (no real rotation) or silently
 * fails to issue new sessions (breaks every mobile client's session
 * refresh).
 */
@ExtendWith(MockitoExtension.class)
class SessionControllerTest {

  @Mock JdbcTemplate db;
  @Mock JwtService jwt;

  private static String sha256Hex(String s) {
    try {
      return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(s.getBytes(StandardCharsets.UTF_8)));
    } catch (Exception e) {
      throw new IllegalStateException(e);
    }
  }

  @Test
  void validTokenRotatesTheSessionAndIssuesFreshTokens() {
    SessionController controller = new SessionController(db, jwt);
    String oldToken = "old-refresh-token-value";
    UUID sessionId = UUID.randomUUID();
    UUID userId = UUID.randomUUID();

    when(db.queryForList(contains("from user_sessions s join users u"), eq(sha256Hex(oldToken))))
        .thenReturn(List.of(Map.of("id", sessionId, "user_id", userId, "email", "driver@example.com")));
    when(db.queryForList(contains("from roles r join user_roles ur"), eq(String.class), eq(userId)))
        .thenReturn(List.of("DRIVER"));
    when(jwt.issue(eq(userId), eq("driver@example.com"), eq(List.of("DRIVER")))).thenReturn("fresh.jwt.token");

    SessionController.Resp resp = controller.refresh(new SessionController.Req(oldToken, "iPhone"));

    assertEquals("fresh.jwt.token", resp.accessToken());
    assertEquals(userId, resp.userId());
    assertNotNull(resp.refreshToken());
    // The whole point of rotation: the token handed back must never be the
    // same string as the one just consumed.
    assertNotEquals(oldToken, resp.refreshToken());

    // The old session is explicitly revoked, not just left to expire on
    // its own -- this is what makes replay of the old token fail
    // immediately rather than merely eventually.
    verify(db).update(eq("update user_sessions set revoked_at=now() where id=?"), eq(sessionId));
    // A brand new session row is created for the new token, hashed (never
    // the raw token itself) before being stored.
    verify(db).update(contains("insert into user_sessions"), eq(userId), eq(sha256Hex(resp.refreshToken())), eq("iPhone"), any());
  }

  @Test
  void unknownTokenRejectedWithoutRevealingWhy() {
    SessionController controller = new SessionController(db, jwt);
    when(db.queryForList(anyString(), anyString())).thenReturn(List.of());

    ApiException ex = assertThrows(ApiException.class,
        () -> controller.refresh(new SessionController.Req("never-issued-token", "device")));

    assertEquals("INVALID_REFRESH_TOKEN", ex.code());
    assertEquals(HttpStatus.UNAUTHORIZED, ex.status());
    verifyNoInteractions(jwt);
  }

  @Test
  void alreadyRotatedTokenCannotBeReplayed() {
    // Exactly the spec's own required scenario (76.8): the real query's
    // own "revoked_at is null" clause means an already-revoked session
    // simply won't be found -- replaying an old, already-rotated token
    // must fail exactly like a token that was never valid at all, not
    // with some different, more revealing error.
    SessionController controller = new SessionController(db, jwt);
    String alreadyRotatedToken = "old-refresh-token-value";
    when(db.queryForList(contains("revoked_at is null"), eq(sha256Hex(alreadyRotatedToken))))
        .thenReturn(List.of());

    ApiException ex = assertThrows(ApiException.class,
        () -> controller.refresh(new SessionController.Req(alreadyRotatedToken, "device")));

    assertEquals("INVALID_REFRESH_TOKEN", ex.code());
    verify(db, never()).update(anyString(), any(Object[].class));
  }
}
