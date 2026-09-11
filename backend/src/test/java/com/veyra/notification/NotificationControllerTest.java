package com.veyra.notification;

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
 * Gap found while cross-checking section 52's test list against the
 * existing suite: no test at all covered the notifications module,
 * despite it being explicitly named. The controller itself is a single
 * trivial endpoint, but the one thing genuinely worth verifying is the
 * privacy rule from section 71 ("CLIENT A ne peut jamais obtenir
 * booking CLIENT B" applies identically to notifications) -- the query
 * must always scope by CurrentUser.id(), never trust a client-supplied
 * user id (there isn't one accepted here, which is itself the correct
 * design -- this test locks that in).
 */
@ExtendWith(MockitoExtension.class)
class NotificationControllerTest {

  @Mock JdbcTemplate db;

  private final UUID userId = UUID.randomUUID();

  @BeforeEach
  void setUpSecurityContext() {
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(userId, null));
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  @Test
  void onlyReturnsNotificationsBelongingToTheCallingUser() {
    when(db.queryForList(contains("where n.user_id=?"), eq(userId)))
        .thenReturn(List.of(Map.of("id", UUID.randomUUID(), "template_code", "NEW_OFFER")));

    List<Map<String, Object>> result = new NotificationController(db).mine();

    assertEquals(1, result.size());
    verify(db).queryForList(contains("where n.user_id=?"), eq(userId));
    // The enriched joins (booking/offer/driver) must not weaken privacy:
    // the query still has exactly one bind parameter and it is the
    // caller's own id, never anything from a request body/path.
    verifyNoMoreInteractions(db);
  }
}
