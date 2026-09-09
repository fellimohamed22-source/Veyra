package com.veyra.location;

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

import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * No test existed at all for this controller before (real gap found
 * while adding the ADMIN/SUPPORT bypass alongside ChatController's
 * identical fix -- both share the same ownership-check shape and the
 * same real need: staff investigating a dispute previously got
 * LOCATION_FORBIDDEN exactly like an uninvolved stranger).
 */
@ExtendWith(MockitoExtension.class)
class BookingLocationControllerTest {

  @Mock JdbcTemplate db;

  private final UUID userId = UUID.randomUUID();
  private final UUID bookingId = UUID.randomUUID();

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  private BookingLocationController controller() {
    return new BookingLocationController(db);
  }

  @Test
  void someoneUninvolvedGetsForbidden() {
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(userId, null));
    when(db.queryForObject(contains("from scheduled_bookings sb left join drivers"), eq(Integer.class), any(Object[].class)))
        .thenReturn(0);

    ApiException ex = assertThrows(ApiException.class, () -> controller().current(bookingId));

    assertEquals("LOCATION_FORBIDDEN", ex.code());
  }

  @Test
  void aParticipantSeesAvailableFalseWhenNoLocationRowExistsYet() {
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(userId, null));
    when(db.queryForObject(contains("from scheduled_bookings sb left join drivers"), eq(Integer.class), any(Object[].class)))
        .thenReturn(1);
    when(db.queryForList(contains("from current_driver_locations"), eq(bookingId)))
        .thenReturn(List.of());

    Map<String, Object> result = controller().current(bookingId);

    assertEquals(false, result.get("available"));
  }

  @Test
  void adminSeesLocationForABookingTheyAreNotAParticipantOf() {
    SecurityContextHolder.getContext().setAuthentication(
        new TestingAuthenticationToken(userId, null, "ROLE_ADMIN"));
    when(db.queryForList(contains("from current_driver_locations"), eq(bookingId)))
        .thenReturn(List.of(Map.of("lat", 43.27, "lng", 6.64)));

    Map<String, Object> result = controller().current(bookingId);

    assertEquals(true, result.get("available"));
    verify(db, never()).queryForObject(contains("from scheduled_bookings sb left join drivers"), eq(Integer.class), any(Object[].class));
  }

  @Test
  void aRegularRoleWithoutAdminOrSupportIsStillSubjectToTheOwnershipCheck() {
    SecurityContextHolder.getContext().setAuthentication(
        new TestingAuthenticationToken(userId, null, "ROLE_DRIVER"));
    when(db.queryForObject(contains("from scheduled_bookings sb left join drivers"), eq(Integer.class), any(Object[].class)))
        .thenReturn(0);

    ApiException ex = assertThrows(ApiException.class, () -> controller().current(bookingId));

    assertEquals("LOCATION_FORBIDDEN", ex.code());
  }
}
