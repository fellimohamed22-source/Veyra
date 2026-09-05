package com.veyra.admin;

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
 * Mostly a data-aggregation endpoint (no real branching logic), but the
 * one thing worth verifying: all four real sources (booking, status
 * history, chat, payments) are genuinely combined into a single
 * response, not silently missing one.
 */
@ExtendWith(MockitoExtension.class)
class SupportControllerTest {

  @Mock JdbcTemplate db;

  @Test
  void timelineCombinesBookingHistoryMessagesAndPaymentsIntoOneResponse() {
    UUID bookingId = UUID.randomUUID();
    when(db.queryForMap(contains("from scheduled_bookings where id=?"), eq(bookingId)))
        .thenReturn(Map.of("id", bookingId, "status", "COMPLETED"));
    when(db.queryForList(contains("from booking_status_history"), eq(bookingId)))
        .thenReturn(List.of(Map.of("from_status", "CONFIRMED", "to_status", "COMPLETED")));
    when(db.queryForList(contains("from chat_messages"), eq(bookingId)))
        .thenReturn(List.of(Map.of("body", "hello")));
    when(db.queryForList(contains("from payments where booking_id=?"), eq(bookingId)))
        .thenReturn(List.of(Map.of("status", "CAPTURED")));

    Map<String, Object> result = new SupportController(db).timeline(bookingId);

    assertNotNull(result.get("booking"));
    assertEquals(1, ((List<?>) result.get("history")).size());
    assertEquals(1, ((List<?>) result.get("messages")).size());
    assertEquals(1, ((List<?>) result.get("payments")).size());
  }
}
