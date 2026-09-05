package com.veyra.chat;

import com.veyra.shared.ApiException;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * Real access-control logic (who can even see or send a booking's chat)
 * had zero coverage before this -- the single query gates on both "is
 * this person actually involved" (creator, selected driver, or active
 * partner staff) AND "has the booking reached a stage where chat should
 * even be open" (not while still just OPEN_FOR_OFFERS). A bug here either
 * locks a legitimate participant out or leaks a booking's conversation to
 * someone uninvolved.
 */
@ExtendWith(MockitoExtension.class)
class ChatControllerTest {

  @Mock JdbcTemplate db;
  @Mock SimpMessagingTemplate ws;

  private final UUID userId = UUID.randomUUID();
  private final UUID bookingId = UUID.randomUUID();

  @BeforeEach
  void setUpSecurityContext() {
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(userId, null));
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  private ChatController controller() {
    return new ChatController(db, ws);
  }

  private void stubParticipant(int count) {
    when(db.queryForObject(contains("from scheduled_bookings sb left join drivers"), eq(Integer.class), any(Object[].class)))
        .thenReturn(count);
  }

  @Test
  void someoneUninvolvedInTheBookingCannotSendAMessage() {
    stubParticipant(0);

    ApiException ex = assertThrows(ApiException.class,
        () -> controller().send(bookingId, new ChatController.Msg("hello")));

    assertEquals("CHAT_NOT_ALLOWED", ex.code());
    assertEquals(HttpStatus.FORBIDDEN, ex.status());
    verifyNoInteractions(ws);
  }

  @Test
  void someoneUninvolvedCannotListMessagesEither() {
    stubParticipant(0);

    ApiException ex = assertThrows(ApiException.class, () -> controller().list(bookingId));

    assertEquals("CHAT_NOT_ALLOWED", ex.code());
  }

  @Test
  void aBlankMessageIsRejected() {
    stubParticipant(1);

    ApiException ex = assertThrows(ApiException.class,
        () -> controller().send(bookingId, new ChatController.Msg("   ")));

    assertEquals("INVALID_MESSAGE", ex.code());
    verifyNoInteractions(ws);
  }

  @Test
  void aMessageOverTwoThousandCharactersIsRejected() {
    stubParticipant(1);
    String tooLong = "x".repeat(2001);

    ApiException ex = assertThrows(ApiException.class,
        () -> controller().send(bookingId, new ChatController.Msg(tooLong)));

    assertEquals("INVALID_MESSAGE", ex.code());
  }

  @Test
  void aParticipantSendingToAnExistingConversationReusesItAndBroadcasts() {
    stubParticipant(1);
    UUID existingConversationId = UUID.randomUUID();
    when(db.queryForList(eq("select id from chat_conversations where booking_id=?"), eq(UUID.class), any(Object[].class)))
        .thenReturn(List.of(existingConversationId));

    ResponseEntity<Map<String, Object>> response = controller().send(bookingId, new ChatController.Msg("hello there"));

    assertEquals(HttpStatus.CREATED, response.getStatusCode());
    assertEquals("hello there", response.getBody().get("body"));
    assertEquals(userId, response.getBody().get("senderUserId"));
    // Must reuse the existing conversation, never create a second one for
    // the same booking.
    verify(db, never()).update(contains("insert into chat_conversations"), any(), any());
    verify(db).update(contains("insert into chat_messages"), any(), eq(existingConversationId), eq(userId), eq("hello there"));
    verify(ws).convertAndSend(eq("/topic/bookings/" + bookingId + "/chat"), any(Map.class));
  }

  @Test
  void firstMessageOnABookingCreatesTheConversation() {
    stubParticipant(1);
    when(db.queryForList(eq("select id from chat_conversations where booking_id=?"), eq(UUID.class), any(Object[].class)))
        .thenReturn(List.of());

    controller().send(bookingId, new ChatController.Msg("first message"));

    verify(db).update(contains("insert into chat_conversations"), any(), eq(bookingId));
  }

  @Test
  void listingMessagesReturnsThemForAnAllowedParticipant() {
    stubParticipant(1);
    when(db.queryForList(contains("from chat_messages cm join chat_conversations"), eq(bookingId)))
        .thenReturn(List.of(Map.of("id", UUID.randomUUID(), "body", "hi")));

    List<Map<String, Object>> messages = controller().list(bookingId);

    assertEquals(1, messages.size());
  }
}
