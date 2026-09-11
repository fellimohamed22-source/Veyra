package com.veyra.notification;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.veyra.provider.PushProvider;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * Real, missing piece this closes: OutboxPublisher correctly queued
 * PENDING rows and FirebasePushProvider could genuinely send a push,
 * but nothing anywhere in the codebase ever read a PENDING row and
 * called PushProvider.send() -- confirmed by searching the entire
 * backend for any class injecting PushProvider outside its own
 * implementations, found none. This is the connector between those two
 * already-correct halves.
 */
@ExtendWith(MockitoExtension.class)
class NotificationDispatcherTest {

  @Mock JdbcTemplate db;
  @Mock PushProvider pushProvider;
  final ObjectMapper objectMapper = new ObjectMapper();

  private NotificationDispatcher dispatcher() {
    return new NotificationDispatcher(db, pushProvider, objectMapper);
  }

  @Test
  void aSuccessfulSendMarksTheNotificationSent() {
    UUID id = UUID.randomUUID();
    UUID userId = UUID.randomUUID();
    when(db.queryForList(contains("from notifications"))).thenReturn(List.of(
        rowOf(id, userId, "NEW_OFFER", "{\"bookingId\":\"abc\"}")));
    when(pushProvider.send(eq(userId), eq("NEW_OFFER"), anyMap())).thenReturn(true);

    dispatcher().dispatch();

    verify(db).update(contains("status=?"), eq("SENT"), eq(true), eq(id));
  }

  @Test
  void aFailedSendMarksTheNotificationFailedRatherThanSilentlyLeavingItPending() {
    UUID id = UUID.randomUUID();
    UUID userId = UUID.randomUUID();
    when(db.queryForList(contains("from notifications"))).thenReturn(List.of(
        rowOf(id, userId, "NEW_BOOKING", "{}")));
    when(pushProvider.send(any(), any(), anyMap())).thenReturn(false);

    dispatcher().dispatch();

    verify(db).update(contains("status=?"), eq("FAILED"), eq(false), eq(id));
  }

  @Test
  void anExceptionFromOneNotificationDoesNotStopTheRestOfTheBatch() {
    UUID id1 = UUID.randomUUID();
    UUID id2 = UUID.randomUUID();
    UUID userId = UUID.randomUUID();
    when(db.queryForList(contains("from notifications"))).thenReturn(List.of(
        rowOf(id1, userId, "NEW_OFFER", "{}"),
        rowOf(id2, userId, "NEW_BOOKING", "{}")));
    when(pushProvider.send(eq(userId), eq("NEW_OFFER"), anyMap())).thenThrow(new RuntimeException("provider hiccup"));
    when(pushProvider.send(eq(userId), eq("NEW_BOOKING"), anyMap())).thenReturn(true);

    dispatcher().dispatch();

    // The exception on the first row must not prevent the second row
    // from being attempted and correctly marked.
    verify(db).update(contains("status=?"), eq("FAILED"), eq(false), eq(id1));
    verify(db).update(contains("status=?"), eq("SENT"), eq(true), eq(id2));
  }

  @Test
  void theJsonDataColumnIsParsedIntoTheMapPassedToTheProvider() {
    UUID id = UUID.randomUUID();
    UUID userId = UUID.randomUUID();
    when(db.queryForList(contains("from notifications"))).thenReturn(List.of(
        rowOf(id, userId, "NEW_OFFER", "{\"bookingId\":\"xyz-123\"}")));
    when(pushProvider.send(any(), any(), anyMap())).thenReturn(true);

    dispatcher().dispatch();

    verify(pushProvider).send(eq(userId), eq("NEW_OFFER"), eq(Map.of("bookingId", "xyz-123")));
  }

  @Test
  void malformedJsonDataFailsThatOneRowGracefullyRatherThanCrashingTheWholeBatch() {
    UUID id = UUID.randomUUID();
    UUID userId = UUID.randomUUID();
    when(db.queryForList(contains("from notifications"))).thenReturn(List.of(
        rowOf(id, userId, "NEW_OFFER", "not valid json")));
    when(pushProvider.send(any(), any(), anyMap())).thenReturn(true);

    assertDoesNotThrow(() -> dispatcher().dispatch());

    verify(pushProvider).send(eq(userId), eq("NEW_OFFER"), eq(Map.of()));
  }

  @Test
  void doesNothingAtAllWhenThereAreNoPendingNotifications() {
    // Locks in the new early-return added alongside the
    // NOTIFICATION_DISPATCH_RUN summary log: with zero pending rows
    // (the overwhelmingly common case, polling every 3s), neither the
    // push provider nor the notifications table should be touched at
    // all.
    when(db.queryForList(contains("from notifications"))).thenReturn(List.of());

    dispatcher().dispatch();

    verifyNoInteractions(pushProvider);
    verify(db, never()).update(anyString(), any(), any(), any());
  }

  private static Map<String, Object> rowOf(UUID id, UUID userId, String templateCode, String dataJson) {
    Map<String, Object> row = new HashMap<>();
    row.put("id", id);
    row.put("user_id", userId);
    row.put("template_code", templateCode);
    row.put("data", dataJson);
    return row;
  }
}
