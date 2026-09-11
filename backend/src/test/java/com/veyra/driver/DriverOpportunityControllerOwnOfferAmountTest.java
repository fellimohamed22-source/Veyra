package com.veyra.driver;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.time.OffsetDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * Real gap closed here: hasActiveOffer already told the mobile app a
 * driver had an offer on this booking, but never the amount itself --
 * needed so the new offer-adjustment UI can pre-fill the price field
 * rather than asking the driver to re-type a number they already know
 * they once entered.
 */
@ExtendWith(MockitoExtension.class)
class DriverOpportunityControllerOwnOfferAmountTest {

  @Mock JdbcTemplate db;

  private final UUID userId = UUID.randomUUID();
  private final UUID driverId = UUID.randomUUID();
  private final UUID bookingId = UUID.randomUUID();

  private DriverOpportunityController controller() {
    return new DriverOpportunityController(db);
  }

  private void asDriver() {
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(userId, null));
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  private void stubEligibleDriver() {
    when(db.queryForList(eq("select id from drivers where user_id=?"), eq(UUID.class), eq(userId)))
        .thenReturn(List.of(driverId));
    when(db.queryForObject(contains("from drivers where id=? and status='ACTIVE'"), eq(Integer.class), eq(driverId)))
        .thenReturn(1);
  }

  private void stubBookingRow() {
    Map<String, Object> row = new HashMap<>();
    row.put("id", bookingId);
    row.put("status", "OFFERS_RECEIVED");
    row.put("offer_window_ends_at", OffsetDateTime.now().plusHours(1));
    row.put("offer_visibility_mode", "PRIVATE");
    when(db.queryForList(contains("from scheduled_bookings sb join vehicle_categories"), eq(bookingId)))
        .thenReturn(List.of(row));
  }

  @Test
  void includesTheDriversOwnOfferAmountWhenOneExists() {
    asDriver();
    stubEligibleDriver();
    stubBookingRow();
    when(db.queryForList(contains("select proposed_amount_minor from driver_offers"), eq(bookingId), eq(driverId)))
        .thenReturn(List.of(Map.of("proposed_amount_minor", 5500L)));

    Map<String, Object> result = controller().detail(bookingId);

    assertEquals(true, result.get("hasActiveOffer"));
    assertEquals(5500L, result.get("ownActiveOfferAmountMinor"));
  }

  @Test
  void omitsTheAmountFieldWhenNoOfferExistsYet() {
    asDriver();
    stubEligibleDriver();
    stubBookingRow();
    when(db.queryForList(contains("select proposed_amount_minor from driver_offers"), eq(bookingId), eq(driverId)))
        .thenReturn(List.of());

    Map<String, Object> result = controller().detail(bookingId);

    assertEquals(false, result.get("hasActiveOffer"));
    assertNull(result.get("ownActiveOfferAmountMinor"));
  }
}
