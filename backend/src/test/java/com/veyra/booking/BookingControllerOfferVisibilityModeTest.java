package com.veyra.booking;

import com.veyra.finance.LedgerService;
import com.veyra.security.PinCrypto;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

/**
 * Real gap this closes: the only existing endpoint for reading the
 * offer-visibility policy (admin/ConfigController) required ROLE_ADMIN
 * -- a client or driver had no way to even see which mode is currently
 * active. This new endpoint is read-only and open to any authenticated
 * user.
 */
@ExtendWith(MockitoExtension.class)
class BookingControllerOfferVisibilityModeTest {

  @Mock JdbcTemplate db;
  @Mock PasswordEncoder enc;
  @Mock PinCrypto pinCrypto;
  @Mock LedgerService ledger;

  private BookingController controller() {
    return new BookingController(db, enc, pinCrypto, ledger, 120L, 24L, 60L, 30L);
  }

  @Test
  void returnsTheCurrentlyActiveMode() {
    when(db.queryForList(contains("from offer_visibility_policy_versions where status='ACTIVE'")))
        .thenReturn(List.of(Map.of("mode", "BEST_VISIBLE")));

    Map<String, Object> result = controller().offerVisibilityMode();

    assertEquals("BEST_VISIBLE", result.get("mode"));
  }

  @Test
  void defaultsToPrivateWhenNoPolicyHasEverBeenConfigured() {
    // A fresh platform with no admin-configured policy row yet must
    // never fail the client's booking flow with a lookup error --
    // PRIVATE is the safe, conservative default (matches this
    // project's baseline design of never showing competing prices
    // unless explicitly opted into BEST_VISIBLE).
    when(db.queryForList(contains("from offer_visibility_policy_versions where status='ACTIVE'")))
        .thenReturn(List.of());

    Map<String, Object> result = controller().offerVisibilityMode();

    assertEquals("PRIVATE", result.get("mode"));
  }
}
