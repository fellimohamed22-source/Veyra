package com.veyra.notification;

import com.veyra.shared.ApiException;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/** CL-18: read state is scoped to the caller's own notifications. */
@ExtendWith(MockitoExtension.class)
class NotificationControllerTest {
  @Mock JdbcTemplate db;
  private final UUID userId = UUID.randomUUID();

  @BeforeEach
  void setUp() { SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(userId, null)); }

  @AfterEach
  void tearDown() { SecurityContextHolder.clearContext(); }

  /**
   * Original check kept: the list query always scopes by the caller's
   * own id (privacy rule, section 71), never a client-supplied user id.
   */
  @Test
  void onlyReturnsNotificationsBelongingToTheCallingUser() {
    when(db.queryForList(contains("where n.user_id=?"), eq(userId)))
        .thenReturn(java.util.List.of(Map.of("id", UUID.randomUUID(), "template_code", "NEW_OFFER")));

    var result = new NotificationController(db).mine();

    assertEquals(1, result.size());
    verify(db).queryForList(contains("where n.user_id=?"), eq(userId));
    verifyNoMoreInteractions(db);
  }

  @Test
  void markingOneReadOnlyTouchesTheCallersRowAndReturnsTheNewCount() {
    UUID id = UUID.randomUUID();
    when(db.update(contains("set read_at=coalesce(read_at,now()) where id=? and user_id=?"), eq(id), eq(userId))).thenReturn(1);
    when(db.queryForObject(contains("read_at is null"), eq(Long.class), eq(userId))).thenReturn(2L);

    assertEquals(Map.of("unread", 2L), new NotificationController(db).read(id));
  }

  @Test
  void someoneElsesNotificationIsNotFound() {
    UUID id = UUID.randomUUID();
    when(db.update(contains("where id=? and user_id=?"), eq(id), eq(userId))).thenReturn(0);
    assertEquals("NOTIFICATION_NOT_FOUND", assertThrows(ApiException.class, () -> new NotificationController(db).read(id)).code());
  }

  @Test
  void readAllClearsTheBadge() {
    when(db.queryForObject(contains("read_at is null"), eq(Long.class), eq(userId))).thenReturn(0L);
    assertEquals(Map.of("unread", 0L), new NotificationController(db).readAll());
    verify(db).update("update notifications set read_at=now() where user_id=? and read_at is null", userId);
  }
}
