package com.veyra.booking;

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

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * No test existed at all for this controller before, despite it being
 * one of the most security-sensitive endpoints in the app (section 24/
 * 25's PIN security requirements). Deliberately does NOT test any
 * ADMIN/SUPPORT bypass, because there isn't one and there deliberately
 * should never be one here -- unlike chat/location/ratings (informational,
 * fixed earlier this session), the PIN is an active security credential
 * gating the DRIVER_ARRIVED -> IN_PROGRESS transition; the entire design
 * intent (confirmed by re-reading section 24: "Le Chauffeur ne doit
 * jamais pouvoir récupérer le PIN lui-même") is that only the customer/
 * partner controls sharing it with the driver. Staff reading it out
 * over the phone would defeat that verification's whole purpose, so
 * this test suite locks in the CURRENT (correct) behavior: creator or
 * active partner_user only, never the driver, and no staff bypass.
 */
@ExtendWith(MockitoExtension.class)
class PinControllerTest {

  @Mock JdbcTemplate db;
  @Mock PinCrypto crypto;

  private final UUID bookingId = UUID.randomUUID();
  private final UUID creatorId = UUID.randomUUID();
  private final UUID partnerId = UUID.randomUUID();

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  private PinController controller() {
    return new PinController(db, crypto);
  }

  private void stubBooking(OffsetDateTime scheduledAt, Object partnerIdOrNull, String pinEncryptedOrNull) {
    Map<String, Object> row = new java.util.HashMap<>();
    row.put("creator_user_id", creatorId);
    row.put("scheduled_at", scheduledAt);
    row.put("status", "CONFIRMED");
    row.put("partner_id", partnerIdOrNull);
    row.put("pin_encrypted", pinEncryptedOrNull);
    when(db.queryForList(contains("from scheduled_bookings where id=?"), eq(bookingId)))
        .thenReturn(List.of(row));
  }

  @Test
  void theCreatorCanFetchThePinOnceWithinTheHMinus1Window() {
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(creatorId, null));
    stubBooking(OffsetDateTime.now().plusMinutes(10), null, "encrypted-value");
    when(crypto.decrypt("encrypted-value")).thenReturn("4271");

    Map<String, Object> result = controller().pin(bookingId);

    assertEquals("4271", result.get("pin"));
  }

  @Test
  void tooEarlyBeforeHMinus1IsRejectedEvenForTheCreator() {
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(creatorId, null));
    stubBooking(OffsetDateTime.now().plusHours(3), null, "encrypted-value");

    ApiException ex = assertThrows(ApiException.class, () -> controller().pin(bookingId));

    assertEquals("PIN_NOT_YET_AVAILABLE", ex.code());
    // The decrypt must never even be attempted this early.
    verifyNoInteractions(crypto);
  }

  @Test
  void someoneUnrelatedToTheBookingIsForbidden() {
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(UUID.randomUUID(), null));
    stubBooking(OffsetDateTime.now().plusMinutes(10), null, "encrypted-value");

    ApiException ex = assertThrows(ApiException.class, () -> controller().pin(bookingId));

    assertEquals("FORBIDDEN", ex.code());
    verifyNoInteractions(crypto);
  }

  @Test
  void anActivePartnerUserCanFetchThePinForTheirOrganizationsBooking() {
    UUID partnerStaffId = UUID.randomUUID();
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(partnerStaffId, null));
    stubBooking(OffsetDateTime.now().plusMinutes(10), partnerId, "encrypted-value");
    when(db.queryForObject(contains("from partner_users where partner_id=? and user_id=?"), eq(Integer.class), eq(partnerId), eq(partnerStaffId)))
        .thenReturn(1);
    when(crypto.decrypt("encrypted-value")).thenReturn("4271");

    Map<String, Object> result = controller().pin(bookingId);

    assertEquals("4271", result.get("pin"));
  }

  @Test
  void noPinCreatedYetIsAConflictNotASilentEmptyValue() {
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(creatorId, null));
    stubBooking(OffsetDateTime.now().plusMinutes(10), null, null);

    ApiException ex = assertThrows(ApiException.class, () -> controller().pin(bookingId));

    assertEquals("PIN_NOT_CREATED", ex.code());
  }
}
