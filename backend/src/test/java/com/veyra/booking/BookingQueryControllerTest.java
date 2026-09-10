package com.veyra.booking;

import com.veyra.shared.ApiException;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * No test existed at all for this controller before. Written while
 * adding timeline() for P32 ("Suivi reservation Partenaire") -- traced
 * assertAllowed()'s actual short-circuit order by hand before writing
 * each stub (unlike DocumentController's admin check, which runs
 * unconditionally and caused a real NPE caught only by the user's
 * pasted test log, this one's two queryForObject calls are genuinely
 * conditional: each only runs if not-yet-allowed AND the relevant id is
 * non-null, so the creator-is-caller path never touches either mock).
 */
@ExtendWith(MockitoExtension.class)
class BookingQueryControllerTest {

  @Mock JdbcTemplate db;

  private final UUID bookingId = UUID.randomUUID();
  private final UUID creatorId = UUID.randomUUID();
  private final UUID partnerId = UUID.randomUUID();
  private final UUID driverId = UUID.randomUUID();

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  private BookingQueryController controller() {
    return new BookingQueryController(db);
  }

  private Map<String, Object> row(Object partnerIdOrNull, Object selectedDriverIdOrNull) {
    Map<String, Object> m = new HashMap<>();
    m.put("creator_user_id", creatorId);
    m.put("partner_id", partnerIdOrNull);
    m.put("selected_driver_id", selectedDriverIdOrNull);
    return m;
  }

  @Test
  void theCreatorNeverTriggersEitherOwnershipQuery() {
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(creatorId, null));
    when(db.queryForList(contains("select creator_user_id,partner_id,selected_driver_id"), eq(bookingId)))
        .thenReturn(List.of(row(partnerId, driverId)));
    when(db.queryForList(contains("from booking_status_history"), eq(bookingId)))
        .thenReturn(List.of(Map.of("to_status", "CONFIRMED")));

    List<Map<String, Object>> result = controller().timeline(bookingId);

    assertEquals(1, result.size());
    verify(db, never()).queryForObject(contains("from partner_users"), eq(Integer.class), any(), any());
    verify(db, never()).queryForObject(contains("from drivers where id=?"), eq(Integer.class), any(), any());
  }

  @Test
  void anActivePartnerMemberCanReadTheTimeline() {
    UUID partnerStaffId = UUID.randomUUID();
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(partnerStaffId, null));
    when(db.queryForList(contains("select creator_user_id,partner_id,selected_driver_id"), eq(bookingId)))
        .thenReturn(List.of(row(partnerId, null)));
    when(db.queryForObject(contains("from partner_users"), eq(Integer.class), eq(partnerId), eq(partnerStaffId)))
        .thenReturn(1);
    when(db.queryForList(contains("from booking_status_history"), eq(bookingId)))
        .thenReturn(List.of());

    assertDoesNotThrow(() -> controller().timeline(bookingId));
  }

  @Test
  void someoneWithNoRelationToTheBookingIsForbidden() {
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(UUID.randomUUID(), null));
    when(db.queryForList(contains("select creator_user_id,partner_id,selected_driver_id"), eq(bookingId)))
        .thenReturn(List.of(row(null, null)));

    ApiException ex = assertThrows(ApiException.class, () -> controller().timeline(bookingId));

    assertEquals("FORBIDDEN", ex.code());
    verify(db, never()).queryForList(contains("from booking_status_history"), eq(bookingId));
  }

  @Test
  void unknownBookingIs404BeforeAnyOwnershipCheck() {
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(UUID.randomUUID(), null));
    when(db.queryForList(contains("select creator_user_id,partner_id,selected_driver_id"), eq(bookingId)))
        .thenReturn(List.of());

    ApiException ex = assertThrows(ApiException.class, () -> controller().timeline(bookingId));

    assertEquals("BOOKING_NOT_FOUND", ex.code());
  }
}
