package com.veyra.booking;

import com.veyra.booking.BookingDtos.Create;
import com.veyra.booking.BookingDtos.Point;
import com.veyra.finance.LedgerService;
import com.veyra.security.PinCrypto;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.time.OffsetDateTime;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * Gap P0 #1 (GAPS_REQUIRED_CHANGES.md / screen P29): the backend used to
 * ONLY snapshot the platform-wide active policy onto every new booking,
 * ignoring any per-booking choice -- so a partner had no way to actually
 * turn BEST_VISIBLE on/off for their own booking as the MVP requires.
 * Membership on partnerId is already validated earlier in create() by
 * member(partnerId,u); these tests only cover the override logic itself.
 */
@ExtendWith(MockitoExtension.class)
class BookingControllerOfferVisibilityOverrideTest {

  @Mock JdbcTemplate db;
  @Mock PasswordEncoder enc;
  @Mock PinCrypto pinCrypto;
  @Mock LedgerService ledger;
  @Mock BookingStatusHistoryService history;

  private final UUID userId = UUID.randomUUID();
  private final UUID partnerId = UUID.randomUUID();

  @BeforeEach
  void setUpSecurityContext() {
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(userId, null));
    // No active service-zone restriction configured -- skips the
    // ST_Covers branch entirely so this test stays focused on the
    // override logic, not geofencing.
    when(db.queryForObject(contains("from service_zone_versions"), eq(Integer.class))).thenReturn(0);
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  private BookingController controller() {
    return new BookingController(db, enc, pinCrypto, ledger, 120L, 24L, 60L, 30L, history);
  }

  private Create request(UUID partner, String offerVisibilityMode) {
    return new Create(
        new Point(43.27, 6.64, "Saint-Tropez"),
        new Point(43.70, 7.27, "Nice Aéroport"),
        OffsetDateTime.now().plusHours(5),
        UUID.randomUUID(),
        "ONLINE",
        partner == null ? "CLIENT" : "PARTNER",
        partner,
        partner == null ? null : "Client du partenaire",
        partner == null ? null : "+33600000000",
        2, 1, null,
        offerVisibilityMode);
  }

  private Object[] capturedInsertArgs() {
    ArgumentCaptor<Object[]> captor = ArgumentCaptor.forClass(Object[].class);
    verify(db).update(contains("insert into scheduled_bookings"), captor.capture());
    return captor.getValue();
  }

  @Test
  void partnerOverrideIsHonoredEvenWhenItDiffersFromTheGlobalPolicy() {
    when(db.queryForObject(contains("from partner_users"), eq(Integer.class), eq(partnerId), eq(userId)))
        .thenReturn(1);
    when(db.queryForObject(contains("from offer_visibility_policy_versions"), eq(String.class)))
        .thenReturn("PRIVATE");

    controller().create(request(partnerId, "BEST_VISIBLE"));

    Object[] args = capturedInsertArgs();
    assertEquals("BEST_VISIBLE", args[args.length - 1]);
  }

  @Test
  void clientBookingIgnoresAnySuppliedOverrideAndAlwaysUsesTheGlobalPolicy() {
    when(db.queryForObject(contains("from offer_visibility_policy_versions"), eq(String.class)))
        .thenReturn("PRIVATE");

    // No partnerId -- even if a client somehow sent offerVisibilityMode,
    // it must never take effect (only PARTNER bookings may override).
    controller().create(request(null, "BEST_VISIBLE"));

    Object[] args = capturedInsertArgs();
    assertEquals("PRIVATE", args[args.length - 1]);
  }

  @Test
  void partnerBookingWithNoOverrideFallsBackToTheGlobalPolicy() {
    when(db.queryForObject(contains("from partner_users"), eq(Integer.class), eq(partnerId), eq(userId)))
        .thenReturn(1);
    when(db.queryForObject(contains("from offer_visibility_policy_versions"), eq(String.class)))
        .thenReturn("BEST_VISIBLE");

    controller().create(request(partnerId, null));

    Object[] args = capturedInsertArgs();
    assertEquals("BEST_VISIBLE", args[args.length - 1]);
  }
}
