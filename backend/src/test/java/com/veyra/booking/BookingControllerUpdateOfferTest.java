package com.veyra.booking;

import com.veyra.finance.LedgerService;
import com.veyra.security.PinCrypto;
import com.veyra.shared.ApiException;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.time.OffsetDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * New feature: a driver adjusting the price of an offer they've already
 * submitted, rather than being permanently locked to their first
 * number for a booking that might stay open for offers for a while.
 * Deliberately narrower than the brand-new-offer endpoint -- does not
 * re-run CASH-debt-limit or eligibility checks, only confirms the
 * driver genuinely owns an active offer here and the window is still
 * open.
 */
@ExtendWith(MockitoExtension.class)
class BookingControllerUpdateOfferTest {

  @Mock JdbcTemplate db;
  @Mock PasswordEncoder enc;
  @Mock PinCrypto pinCrypto;
  @Mock LedgerService ledger;

  private final UUID driverUserId = UUID.randomUUID();
  private final UUID driverId = UUID.randomUUID();
  private final UUID bookingId = UUID.randomUUID();

  private BookingController controller() {
    return new BookingController(db, enc, pinCrypto, ledger, 120L, 24L, 60L, 30L);
  }

  private void asDriver() {
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(driverUserId, null));
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  private void stubDriverLookup() {
    when(db.queryForList(eq("select id from drivers where user_id=?"), eq(UUID.class), eq(driverUserId)))
        .thenReturn(List.of(driverId));
  }

  private void stubBooking(String status, OffsetDateTime windowEnds) {
    Map<String, Object> row = new HashMap<>();
    row.put("status", status);
    row.put("offer_window_ends_at", windowEnds);
    when(db.queryForList(contains("from scheduled_bookings where id=? for update"), eq(bookingId)))
        .thenReturn(List.of(row));
  }

  @Test
  void updatingTheAmountOnAGenuineActiveOfferSucceeds() {
    asDriver();
    stubDriverLookup();
    stubBooking("OFFERS_RECEIVED", OffsetDateTime.now().plusHours(2));
    UUID offerId = UUID.randomUUID();
    when(db.queryForList(contains("from driver_offers where booking_id=? and driver_id=? and status='ACTIVE'"), eq(bookingId), eq(driverId)))
        .thenReturn(List.of(offerId));
    when(db.queryForObject(contains("offer_visibility_mode"), eq(String.class), eq(bookingId))).thenReturn("PRIVATE");

    Map<String, Object> result = controller().updateOffer(bookingId, new BookingDtos.Offer(5500, "EUR"));

    assertEquals(offerId, result.get("offerId"));
    verify(db).update(contains("update driver_offers set proposed_amount_minor=?,currency=?"), eq(5500L), eq("EUR"), eq(offerId));
  }

  @Test
  void cannotAdjustAnOfferThatWasNeverSubmitted() {
    asDriver();
    stubDriverLookup();
    stubBooking("OFFERS_RECEIVED", OffsetDateTime.now().plusHours(2));
    when(db.queryForList(contains("from driver_offers where booking_id=? and driver_id=? and status='ACTIVE'"), eq(bookingId), eq(driverId)))
        .thenReturn(List.of());

    ApiException ex = assertThrows(ApiException.class, () -> controller().updateOffer(bookingId, new BookingDtos.Offer(5500, "EUR")));

    assertEquals("NO_ACTIVE_OFFER", ex.code());
    verify(db, never()).update(contains("proposed_amount_minor"), any(), any(), any());
  }

  @Test
  void cannotAdjustAfterTheOfferWindowHasClosed() {
    asDriver();
    stubDriverLookup();
    stubBooking("OFFERS_RECEIVED", OffsetDateTime.now().minusMinutes(1));

    ApiException ex = assertThrows(ApiException.class, () -> controller().updateOffer(bookingId, new BookingDtos.Offer(5500, "EUR")));

    assertEquals("OFFERS_CLOSED", ex.code());
  }

  @Test
  void cannotAdjustOnceTheBookingIsNoLongerOpenForOffers() {
    asDriver();
    stubDriverLookup();
    stubBooking("CONFIRMED", OffsetDateTime.now().plusHours(2));

    ApiException ex = assertThrows(ApiException.class, () -> controller().updateOffer(bookingId, new BookingDtos.Offer(5500, "EUR")));

    assertEquals("OFFERS_CLOSED", ex.code());
  }

  @Test
  void bestVisibleModeReturnsTheCurrentBestOtherOfferAfterAdjusting() {
    asDriver();
    stubDriverLookup();
    stubBooking("OFFERS_RECEIVED", OffsetDateTime.now().plusHours(2));
    UUID offerId = UUID.randomUUID();
    when(db.queryForList(contains("from driver_offers where booking_id=? and driver_id=? and status='ACTIVE'"), eq(bookingId), eq(driverId)))
        .thenReturn(List.of(offerId));
    when(db.queryForObject(contains("offer_visibility_mode"), eq(String.class), eq(bookingId))).thenReturn("BEST_VISIBLE");
    when(db.queryForObject(contains("min(proposed_amount_minor)"), eq(Long.class), eq(bookingId), eq(driverId))).thenReturn(4200L);

    Map<String, Object> result = controller().updateOffer(bookingId, new BookingDtos.Offer(5500, "EUR"));

    assertEquals(4200L, result.get("currentBestOtherOfferMinor"));
    assertNull(result.get("differenceFromBestMinor"));
  }
}
