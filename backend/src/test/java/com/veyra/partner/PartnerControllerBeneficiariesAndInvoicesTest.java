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
 * Two gaps closed here (GAPS_REQUIRED_CHANGES.md #3 and #4):
 * - GET beneficiaries (screen P33) only had a POST before -- a partner
 *   could create beneficiaries but never list the ones already created.
 * - GET invoices (screen P34), deliberately a NEW endpoint under
 *   /partner/ rather than widening PartnerInvoiceController's existing
 *   FINANCE/ADMIN-only endpoint -- a partner's own member had no read
 *   access to their own invoices at all before this.
 * Both must reuse the same member() membership check as every other
 * partner-scoped endpoint in this controller.
 */
@ExtendWith(MockitoExtension.class)
class PartnerControllerBeneficiariesAndInvoicesTest {

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

  private PartnerController controller() {
    return new PartnerController(db);
  }

  private void stubActiveMember() {
    when(db.queryForObject(contains("from partner_users where partner_id=? and user_id=? and status='ACTIVE'"),
        eq(Integer.class), eq(partnerId), eq(userId))).thenReturn(1);
  }

  @Test
  void beneficiariesRejectsNonMembers() {
    when(db.queryForObject(contains("from partner_users where partner_id=? and user_id=? and status='ACTIVE'"),
        eq(Integer.class), eq(partnerId), eq(userId))).thenReturn(0);

    assertThrows(AccessDeniedException.class, () -> controller().beneficiaries(partnerId));
  }

  @Test
  void beneficiariesReturnsTheListScopedToThatPartner() {
    stubActiveMember();
    when(db.queryForList(contains("from partner_beneficiaries where partner_id=?"), eq(partnerId)))
        .thenReturn(List.of(Map.of("id", UUID.randomUUID(), "full_name", "Jean Dupont")));

    List<Map<String, Object>> result = controller().beneficiaries(partnerId);

    assertEquals(1, result.size());
    verify(db).queryForList(contains("where partner_id=?"), eq(partnerId));
  }

  @Test
  void invoicesRejectsNonMembers() {
    when(db.queryForObject(contains("from partner_users where partner_id=? and user_id=? and status='ACTIVE'"),
        eq(Integer.class), eq(partnerId), eq(userId))).thenReturn(0);

    assertThrows(AccessDeniedException.class, () -> controller().invoices(partnerId));
  }

  @Test
  void invoicesReturnsTheListScopedToThatPartnerOnly() {
    stubActiveMember();
    when(db.queryForList(contains("from partner_invoices pi where pi.partner_id=?"), eq(partnerId)))
        .thenReturn(List.of(Map.of("id", UUID.randomUUID(), "status", "ISSUED")));

    List<Map<String, Object>> result = controller().invoices(partnerId);

    assertEquals(1, result.size());
    verify(db).queryForList(contains("pi.partner_id=?"), eq(partnerId));
  }
}
