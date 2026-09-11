package com.veyra.driver;

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
 * Gap P0 closed here (GAPS_REQUIRED_CHANGES.md #2 / screen D18): "Mes
 * offres" had no dedicated endpoint at all -- driver_offers already had
 * everything needed, nothing exposed it scoped to the calling driver.
 */
@ExtendWith(MockitoExtension.class)
class DriverOffersControllerTest {

  @Mock JdbcTemplate db;

  private final UUID userId = UUID.randomUUID();
  private final UUID driverId = UUID.randomUUID();

  @BeforeEach
  void setUpSecurityContext() {
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(userId, null));
    lenient().when(db.queryForList(eq("select id from drivers where user_id=?"), eq(UUID.class), eq(userId)))
        .thenReturn(List.of(driverId));
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  private DriverOffersController controller() {
    return new DriverOffersController(db);
  }

  @Test
  void activeScopeFiltersByStatusActiveAndTheCallingDriverOnly() {
    when(db.queryForList(contains("o.status='ACTIVE'"), eq(driverId)))
        .thenReturn(List.of(Map.of("offer_id", UUID.randomUUID(), "status", "ACTIVE")));

    List<Map<String, Object>> result = controller().list("active");

    assertEquals(1, result.size());
    verify(db).queryForList(contains("where o.driver_id=? and o.status='ACTIVE'"), eq(driverId));
  }

  @Test
  void wonScopeFiltersByAcceptedStatus() {
    when(db.queryForList(contains("o.status='ACCEPTED'"), eq(driverId))).thenReturn(List.of());

    controller().list("won");

    verify(db).queryForList(contains("o.status='ACCEPTED'"), eq(driverId));
  }

  @Test
  void closedScopeCoversRejectedExpiredAndWithdrawn() {
    when(db.queryForList(contains("REJECTED_BY_SELECTION"), eq(driverId))).thenReturn(List.of());

    controller().list("closed");

    // SUPERSEDED added alongside the offer-price-adjustment history fix
    // earlier this session: an offer replaced by a driver's own revised
    // one is genuinely closed (not the current live offer anymore),
    // same practical bucket as rejected/expired/withdrawn even though
    // the underlying reason differs. This test's expected SQL string
    // was not updated at the time -- caught here from the real CI
    // failure log, not by re-reading every call site by hand.
    verify(db).queryForList(
        contains("o.status in ('REJECTED_BY_SELECTION','EXPIRED','WITHDRAWN','SUPERSEDED')"), eq(driverId));
  }

  @Test
  void rejectsAnyScopeOutsideTheAllowedThree() {
    assertThrows(ApiException.class, () -> controller().list("everything"));
  }

  @Test
  void requiresAnExistingDriverProfile() {
    when(db.queryForList(eq("select id from drivers where user_id=?"), eq(UUID.class), eq(userId)))
        .thenReturn(List.of());

    assertThrows(ApiException.class, () -> controller().list("active"));
  }
}
