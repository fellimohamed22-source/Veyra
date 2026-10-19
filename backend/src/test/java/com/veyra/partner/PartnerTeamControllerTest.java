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
    return new PartnerTeamController(db, new org.springframework.beans.factory.support.StaticListableBeanFactory().getBeanProvider(org.springframework.mail.javamail.JavaMailSender.class));
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

    assertThrows(com.veyra.shared.ApiException.class,
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

  @Test
  void invitingAnExistingAccountAttachesItWithTheRole() {
    stubOwner(1);
    UUID invited = UUID.randomUUID();
    when(db.queryForList(contains("from users where lower(email::text)=?"), eq(UUID.class), eq("compta@lemarceau.fr"))).thenReturn(List.of(invited));

    assertEquals(Map.of("status", "ACTIVE"), controller().invite(partnerId, new PartnerTeamController.Invite(" Compta@LeMarceau.fr ", "PARTNER_FINANCE")));

    verify(db).update(contains("insert into partner_users"), eq(partnerId), eq(invited), eq("PARTNER_FINANCE"));
    verify(db, never()).update(contains("insert into partner_invitations"), any(Object[].class));
  }

  @Test
  void invitingAnUnknownAddressKeepsAPendingInvitation() {
    stubOwner(1);
    when(db.queryForList(contains("from users where lower(email::text)=?"), eq(UUID.class), eq("nouveau@lemarceau.fr"))).thenReturn(List.of());

    assertEquals(Map.of("status", "INVITED"), controller().invite(partnerId, new PartnerTeamController.Invite("nouveau@lemarceau.fr", "PARTNER_STAFF")));

    verify(db).update(contains("insert into partner_invitations"), eq(partnerId), eq("nouveau@lemarceau.fr"), eq("PARTNER_STAFF"), eq(userId));
  }

  @Test
  void anInvalidEmailIsRefused() {
    stubOwner(1);
    assertEquals("EMAIL_INVALID", assertThrows(com.veyra.shared.ApiException.class,
        () -> controller().invite(partnerId, new PartnerTeamController.Invite("pas-un-email", "PARTNER_STAFF"))).code());
  }

  @Test
  void anOwnerCannotDeactivateThemselves() {
    stubOwner(1);
    UUID self = UUID.randomUUID();
    when(db.queryForObject(contains("where id=? and partner_id=? and user_id=?"), eq(Integer.class), eq(self), eq(partnerId), eq(userId))).thenReturn(1);

    assertEquals("CANNOT_CHANGE_OWN_MEMBERSHIP", assertThrows(com.veyra.shared.ApiException.class,
        () -> controller().deactivate(partnerId, self)).code());
    verify(db, never()).update(contains("set status='INACTIVE'"), any(Object[].class));
  }
}
