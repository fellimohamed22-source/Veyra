package com.veyra.booking;

import com.veyra.finance.LedgerService;
import com.veyra.security.PinCrypto;
import com.veyra.shared.ApiException;
import org.junit.jupiter.api.AfterEach;
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
  @Mock BookingStatusHistoryService history;

  private final UUID driverUserId = UUID.randomUUID();
  private final UUID driverId = UUID.randomUUID();
  private final UUID bookingId = UUID.randomUUID();

  private BookingController controller() {
    return new BookingController(db, enc, pinCrypto, ledger, 120L, 24L, 60L, 30L, history);
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

  private final UUID policyId = UUID.randomUUID();

  private void stubEligibleDriverWithVehicle() {
    when(db.queryForObject(contains("from drivers where id=? and status='ACTIVE'"), eq(Integer.class), eq(driverId))).thenReturn(1);
    when(db.queryForObject(contains("from driver_documents where driver_id=?"), eq(Integer.class), eq(driverId))).thenReturn(0);
    when(db.queryForObject(contains("from scheduled_bookings sb where sb.id=? and exists"), eq(Integer.class), eq(bookingId), eq(driverId))).thenReturn(1);
  }

  private void stubStandardPolicy(int bps) {
    Map<String, Object> account = new HashMap<>();
    account.put("creator_type", "CLIENT");
    account.put("creator_user_id", UUID.randomUUID());
    account.put("partner_id", null);
    when(db.queryForList(contains("from scheduled_bookings sb left join partner_organizations"), eq(bookingId)))
        .thenReturn(List.of(account));
    when(db.queryForList(contains("from commission_policy_versions"), any(Object[].class)))
        .thenReturn(List.of(Map.of("id", policyId, "commission_bps", bps)));
  }

  @Test
  void adjustingSupersedesTheOldOfferAndInsertsANewOneRatherThanOverwriting() {
    // History explicitly requested by the user: this used to be a
    // straight UPDATE on the same row, silently overwriting the
    // original price with no trace it had ever changed. Now the old
    // ACTIVE row must be marked SUPERSEDED (not deleted, not left
    // ACTIVE) and a brand new ACTIVE row inserted for the revised
    // amount -- verified as two distinct db.update() calls, correlating
    // the newly-generated id via ArgumentCaptor since the method
    // generates it internally (UUID.randomUUID()), not something a test
    // can predict in advance.
    asDriver();
    stubDriverLookup();
    stubBooking("OFFERS_RECEIVED", OffsetDateTime.now().plusHours(2));
    UUID oldOfferId = UUID.randomUUID();
    when(db.queryForList(contains("from driver_offers where booking_id=? and driver_id=? and status='ACTIVE'"), eq(UUID.class), eq(bookingId), eq(driverId)))
        .thenReturn(List.of(oldOfferId));
    when(db.queryForObject(contains("offer_visibility_mode"), eq(String.class), eq(bookingId))).thenReturn("PRIVATE");
    stubStandardPolicy(1000);
    stubEligibleDriverWithVehicle();

    Map<String, Object> result = controller().updateOffer(bookingId, new BookingDtos.Offer(5500, "EUR"));

    verify(db).update(contains("set status='SUPERSEDED' where booking_id=? and driver_id=? and status='ACTIVE'"), eq(bookingId), eq(driverId));

    // The revised offer carries its own frozen commission snapshot.
    ArgumentCaptor<UUID> newIdCaptor = ArgumentCaptor.forClass(UUID.class);
    verify(db).update(
        contains("insert into driver_offers(id,booking_id,driver_id,proposed_amount_minor,currency,status,expires_at,commission_policy_id,commission_rate_bps,commission_minor,customer_total_minor)"),
        newIdCaptor.capture(), eq(bookingId), eq(driverId), eq(5500L), eq("EUR"), any(), eq(policyId), eq(1000), eq(550L), eq(6050L));

    UUID newOfferId = newIdCaptor.getValue();
    assertNotEquals(oldOfferId, newOfferId);
    assertEquals(newOfferId, result.get("offerId"));
    assertEquals(6050L, result.get("customerTotalMinor"));
  }

  @Test
  void suspendedDriverCannotReviseAnExistingOffer() {
    asDriver();
    stubDriverLookup();
    stubBooking("OFFERS_RECEIVED", OffsetDateTime.now().plusHours(2));
    when(db.queryForList(contains("from driver_offers where booking_id=? and driver_id=? and status='ACTIVE'"), eq(UUID.class), eq(bookingId), eq(driverId)))
        .thenReturn(List.of(UUID.randomUUID()));
    when(db.queryForObject(contains("from drivers where id=? and status='ACTIVE'"), eq(Integer.class), eq(driverId))).thenReturn(0);

    ApiException ex = assertThrows(ApiException.class, () -> controller().updateOffer(bookingId, new BookingDtos.Offer(5500, "EUR")));

    assertEquals("DRIVER_NOT_ELIGIBLE", ex.code());
    verify(db, never()).update(contains("SUPERSEDED"), any(), any());
  }

  @Test
  void driverWithoutAnApprovedVehicleOfTheCategoryCannotRevise() {
    asDriver();
    stubDriverLookup();
    stubBooking("OFFERS_RECEIVED", OffsetDateTime.now().plusHours(2));
    when(db.queryForList(contains("from driver_offers where booking_id=? and driver_id=? and status='ACTIVE'"), eq(UUID.class), eq(bookingId), eq(driverId)))
        .thenReturn(List.of(UUID.randomUUID()));
    when(db.queryForObject(contains("from driver_documents where driver_id=?"), eq(Integer.class), eq(driverId))).thenReturn(0);
    when(db.queryForObject(contains("from drivers where id=? and status='ACTIVE'"), eq(Integer.class), eq(driverId))).thenReturn(1);
    when(db.queryForObject(contains("from scheduled_bookings sb where sb.id=? and exists"), eq(Integer.class), eq(bookingId), eq(driverId))).thenReturn(0);

    ApiException ex = assertThrows(ApiException.class, () -> controller().updateOffer(bookingId, new BookingDtos.Offer(5500, "EUR")));

    assertEquals("NO_ELIGIBLE_VEHICLE", ex.code());
  }

  @Test
  void cannotAdjustAnOfferThatWasNeverSubmitted() {
    asDriver();
    stubDriverLookup();
    stubBooking("OFFERS_RECEIVED", OffsetDateTime.now().plusHours(2));
    when(db.queryForList(contains("from driver_offers where booking_id=? and driver_id=? and status='ACTIVE'"), eq(UUID.class), eq(bookingId), eq(driverId)))
        .thenReturn(List.of());

    ApiException ex = assertThrows(ApiException.class, () -> controller().updateOffer(bookingId, new BookingDtos.Offer(5500, "EUR")));

    assertEquals("NO_ACTIVE_OFFER", ex.code());
    verify(db, never()).update(contains("SUPERSEDED"), any(), any());
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
    UUID oldOfferId = UUID.randomUUID();
    when(db.queryForList(contains("from driver_offers where booking_id=? and driver_id=? and status='ACTIVE'"), eq(UUID.class), eq(bookingId), eq(driverId)))
        .thenReturn(List.of(oldOfferId));
    when(db.queryForObject(contains("offer_visibility_mode"), eq(String.class), eq(bookingId))).thenReturn("BEST_VISIBLE");
    when(db.queryForObject(contains("min(proposed_amount_minor)"), eq(Long.class), eq(bookingId), eq(driverId))).thenReturn(4200L);
    stubStandardPolicy(1000);
    stubEligibleDriverWithVehicle();

    Map<String, Object> result = controller().updateOffer(bookingId, new BookingDtos.Offer(5500, "EUR"));

    assertEquals(4200L, result.get("currentBestOtherOfferMinor"));
    assertNull(result.get("differenceFromBestMinor"));
  }
}
