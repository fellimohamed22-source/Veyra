package com.veyra.partner;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * Real access-control logic (only an active PARTNER_OWNER may view or
 * manage team members) plus role-value validation had zero coverage
 * before this -- a non-owner staff member managing their own colleagues'
 * roles would be a real privilege-escalation-adjacent gap.
 */
@ExtendWith(MockitoExtension.class)
class PartnerTeamControllerTest {

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

  private PartnerTeamController controller() {
    return new PartnerTeamController(db);
  }

  private void stubOwner(int count) {
    when(db.queryForObject(contains("partner_role='PARTNER_OWNER'"), eq(Integer.class), eq(partnerId), eq(userId)))
        .thenReturn(count);
  }

  @Test
  void someoneWhoIsNotAnActiveOwnerCannotListTheTeam() {
    stubOwner(0);

    assertThrows(AccessDeniedException.class, () -> controller().list(partnerId));
  }

  @Test
  void someoneWhoIsNotAnActiveOwnerCannotAddATeamMember() {
    stubOwner(0);

    assertThrows(AccessDeniedException.class,
        () -> controller().add(partnerId, new PartnerTeamController.Add(UUID.randomUUID(), "PARTNER_STAFF")));

    verify(db, never()).update(anyString(), any(Object[].class));
  }

  @Test
  void anOwnerCanListTheTeam() {
    stubOwner(1);
    when(db.queryForList(contains("from partner_users pu join users u"), eq(partnerId)))
        .thenReturn(List.of(Map.of("id", UUID.randomUUID(), "email", "staff@example.com")));

    List<Map<String, Object>> team = controller().list(partnerId);

    assertEquals(1, team.size());
  }

  @Test
  void anInvalidRoleIsRejectedEvenForAnOwner() {
    stubOwner(1);

    assertThrows(IllegalArgumentException.class,
        () -> controller().add(partnerId, new PartnerTeamController.Add(UUID.randomUUID(), "SUPER_ADMIN")));

    verify(db, never()).update(anyString(), any(Object[].class));
  }

  @Test
  void anOwnerAddingAValidRoleUpsertsTheMembership() {
    stubOwner(1);
    UUID newUserId = UUID.randomUUID();

    controller().add(partnerId, new PartnerTeamController.Add(newUserId, "PARTNER_FINANCE"));

    verify(db).update(contains("on conflict(partner_id,user_id) do update"), eq(partnerId), eq(newUserId), eq("PARTNER_FINANCE"));
  }
}
