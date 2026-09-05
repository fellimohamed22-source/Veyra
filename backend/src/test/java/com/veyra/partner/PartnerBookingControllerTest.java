package com.veyra.partner;

import com.veyra.shared.ApiException;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
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
 * Real scope-isolation check had zero coverage: a user must be an active
 * member of the partner organization to see its bookings at all -- the
 * one thing standing between two unrelated partner organizations' booking
 * lists.
 */
@ExtendWith(MockitoExtension.class)
class PartnerBookingControllerTest {

  @Mock JdbcTemplate db;

  private final UUID userId = UUID.randomUUID();
  private final UUID partnerId = UUID.randomUUID();

  @BeforeEach
  void setUpSecurityContext() {
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(userId, null));
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  private PartnerBookingController controller() {
    return new PartnerBookingController(db);
  }

  @Test
  void someoneNotAMemberOfThePartnerCannotSeeItsBookings() {
    when(db.queryForObject(anyString(), eq(Integer.class), eq(partnerId), eq(userId))).thenReturn(0);

    ApiException ex = assertThrows(ApiException.class, () -> controller().list(partnerId));

    assertEquals("PARTNER_SCOPE_FORBIDDEN", ex.code());
    assertEquals(HttpStatus.FORBIDDEN, ex.status());
  }

  @Test
  void anActiveMemberSeesThePartnersBookings() {
    when(db.queryForObject(anyString(), eq(Integer.class), eq(partnerId), eq(userId))).thenReturn(1);
    when(db.queryForList(contains("from scheduled_bookings where partner_id=?"), eq(partnerId)))
        .thenReturn(List.of(Map.of("id", UUID.randomUUID(), "status", "CONFIRMED")));

    List<Map<String, Object>> bookings = controller().list(partnerId);

    assertEquals(1, bookings.size());
  }
}
