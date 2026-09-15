package com.veyra.notification;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * No test existed at all for this class before -- written while
 * tracing the full offer.created -> NEW_OFFER -> push pipeline
 * end to end. Unit-test scope limitation, stated plainly: this
 * verifies the exact SQL and arguments OutboxPublisher sends to
 * JdbcTemplate (the recipient selection is "select creator_user_id ...
 * from scheduled_bookings where id=?", scoped to the correct
 * bookingId) -- it cannot verify that creator_user_id actually holds
 * the right person for a real booking row, which is a database-level
 * fact no unit test mocking JdbcTemplate can observe. That part needs
 * either an integration test against a real database or manual
 * verification against the actual row for the tested booking (the
 * user's own step 6).
 */
@ExtendWith(MockitoExtension.class)
class OutboxPublisherTest {

  @Mock JdbcTemplate db;

  private OutboxPublisher publisher() {
    return new OutboxPublisher(db);
  }

  private Map<String, Object> outboxRow(UUID eventId, String type, UUID bookingId) {
    return Map.of(
        "id", eventId,
        "event_type", type,
        "aggregate_id", bookingId,
        "payload", Map.of());
  }

  @Test
  void offerCreatedInsertsANewOfferNotificationScopedToTheBookingsCreator() {
    UUID eventId = UUID.randomUUID();
    UUID bookingId = UUID.randomUUID();
    when(db.queryForList(contains("from outbox_events")))
        .thenReturn(List.of(outboxRow(eventId, "offer.created", bookingId)));
    when(db.update(
        contains("select creator_user_id"),
        eq("offer.created"),eq(eventId),eq(bookingId),eq(eventId),eq(bookingId)))
        .thenReturn(1);

    publisher().publish();

    verify(db).update(
        argThat(sql -> sql.contains("select creator_user_id") &&
            sql.contains("'PUSH','NEW_OFFER'") &&
            sql.contains("'offerId'") &&
            sql.contains("from scheduled_bookings where id=?")),
        eq("offer.created"),eq(eventId),eq(bookingId),eq(eventId),eq(bookingId));
  }

  @Test
  void everyProcessedEventGetsMarkedPublished() {
    UUID eventId = UUID.randomUUID();
    UUID bookingId = UUID.randomUUID();
    when(db.queryForList(contains("from outbox_events")))
        .thenReturn(List.of(outboxRow(eventId, "offer.created", bookingId)));
    when(db.update(contains("select creator_user_id"), any(), any(), any(), any(), any())).thenReturn(1);

    publisher().publish();

    verify(db).update(contains("set published_at=now()"), eq((Object) eventId));
  }

  @Test
  void anUnmappedEventTypeStillGetsMarkedPublishedWithoutInsertingAnyNotification() {
    // Real, plausible failure mode if some other event_type ever
    // reaches this table without a matching branch here -- confirms
    // the event is still consumed (not stuck reprocessing forever) even
    // though nothing recognizes it, rather than silently looping.
    UUID eventId = UUID.randomUUID();
    UUID bookingId = UUID.randomUUID();
    when(db.queryForList(contains("from outbox_events")))
        .thenReturn(List.of(outboxRow(eventId, "payment.captured", bookingId)));

    publisher().publish();

    verify(db, never()).update(contains("into notifications"), any(), any(), any(), any());
    verify(db).update(contains("set published_at=now()"), eq((Object) eventId));
  }

  @Test
  void doesNothingAtAllWhenThereAreNoUnpublishedEvents() {
    when(db.queryForList(contains("from outbox_events"))).thenReturn(List.of());

    publisher().publish();

    verify(db, never()).update(contains("into notifications"), any(), any(), any(), any());
    verify(db, never()).update(contains("set published_at=now()"), any(Object.class));
  }
}
