package com.veyra.driver;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.time.LocalDate;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * KYC onboarding data (company registration, VTC card, vehicles) --
 * lighter business logic than auth/payments/cancellation, but the one
 * real thing worth verifying here is that every write is scoped to the
 * calling driver's own row (via CurrentUser -> driver() lookup), not an
 * id taken from client input, and that company/VTC registration are
 * genuine upserts (a driver correcting a typo in their SIREN must update
 * the existing row, not create a duplicate).
 */
@ExtendWith(MockitoExtension.class)
class DriverOnboardingControllerTest {

  @Mock JdbcTemplate db;

  private final UUID userId = UUID.randomUUID();
  private final UUID driverId = UUID.randomUUID();

  @BeforeEach
  void setUpSecurityContext() {
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(userId, null));
    lenient().when(db.queryForObject(eq("select id from drivers where user_id=?"), eq(UUID.class), any(Object[].class)))
        .thenReturn(driverId);
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  private DriverOnboardingController controller() {
    return new DriverOnboardingController(db);
  }

  @Test
  void companyRegistrationIsScopedToTheCallingDriverAndUpserts() {
    controller().company(new DriverOnboardingController.Company("123456789", "12345678900012", "Jean Transport SARL"));

    verify(db).update(
        contains("on conflict(driver_id) do update"),
        eq(driverId), eq("123456789"), eq("12345678900012"), eq("Jean Transport SARL"), isNull(), isNull());
  }

  @Test
  void vtcRegistrationIsScopedToTheCallingDriverAndUpserts() {
    LocalDate issued = LocalDate.of(2024, 1, 1);
    LocalDate expires = LocalDate.of(2029, 1, 1);

    controller().vtc(new DriverOnboardingController.Vtc("REG-123", "CARD-456", issued, expires));

    verify(db).update(
        contains("on conflict(driver_id) do update"),
        eq(driverId), eq("REG-123"), eq("CARD-456"), eq(issued), eq(expires));
  }

  @Test
  void vehicleIsCreatedForTheCallingDriverWithARealGeneratedId() {
    UUID categoryId = UUID.randomUUID();

    Map<String, UUID> result = controller().vehicle(
        new DriverOnboardingController.Vehicle(categoryId, "Mercedes", "E-Class", 2023, "AB-123-CD", "Black"));

    assertNotNull(result.get("vehicleId"));
    verify(db).update(
        contains("insert into vehicles"),
        eq(result.get("vehicleId")), eq(driverId), eq(categoryId), eq("Mercedes"), eq("E-Class"), eq(2023), eq("AB-123-CD"), eq("Black"), isNull(), isNull());
  }

  @Test
  void statusIsLookedUpForTheCallingDriversOwnRowOnly() {
    when(db.queryForMap(eq("select status,kyc_status,marketplace_enabled,rating,birth_date,driver_type from drivers where id=?"), eq(driverId)))
        .thenReturn(Map.of("status", "ACTIVE", "kyc_status", "APPROVED", "marketplace_enabled", true, "rating", 4.8));

    Map<String, Object> status = controller().status();

    assertEquals("ACTIVE", status.get("status"));
    assertEquals("APPROVED", status.get("kyc_status"));
  }

  @Test
  void birthDateMustBeAnAdultAndTypeKnown() {
    var tooYoung = new DriverOnboardingController.Profile(LocalDate.now().minusYears(17), null);
    assertEquals("BIRTH_DATE_INVALID", assertThrows(com.veyra.shared.ApiException.class, () -> controller().profile(tooYoung)).code());
    var badType = new DriverOnboardingController.Profile(null, "freelance");
    assertEquals("DRIVER_TYPE_INVALID", assertThrows(com.veyra.shared.ApiException.class, () -> controller().profile(badType)).code());

    LocalDate born = LocalDate.of(1985, 3, 15);
    controller().profile(new DriverOnboardingController.Profile(born, "independent"));
    verify(db).update(contains("update drivers set birth_date"), eq(born), eq("INDEPENDENT"), eq(driverId));
  }

  @Test
  void licenseNeedsNumberKnownCategoryAndNoPastExpiry() {
    assertEquals("LICENSE_CATEGORY_INVALID", assertThrows(com.veyra.shared.ApiException.class,
        () -> controller().license(new DriverOnboardingController.License("12AB34567", "Z", null))).code());
    assertEquals("LICENSE_EXPIRED", assertThrows(com.veyra.shared.ApiException.class,
        () -> controller().license(new DriverOnboardingController.License("12AB34567", "B", LocalDate.now().minusDays(1)))).code());

    LocalDate expires = LocalDate.now().plusYears(4);
    controller().license(new DriverOnboardingController.License(" 12AB34567 ", "b", expires));
    verify(db).update(contains("insert into driver_licenses"), eq(driverId), eq("12AB34567"), eq("B"), eq(expires));
  }

  @Test
  void incompleteDossierIsNotSubmitted() {
    var response = controller().submit();

    assertEquals(422, response.getStatusCode().value());
    @SuppressWarnings("unchecked")
    var missing = (java.util.List<String>) response.getBody().get("missing");
    assertTrue(missing.containsAll(java.util.List.of("BIRTH_DATE", "IDENTITY", "INSURANCE", "VEHICLE_REGISTRATION", "LICENSE", "VEHICLE")));
    verify(db, never()).update(contains("kyc_status='SUBMITTED'"), any(Object[].class));
  }

  @Test
  void completeDossierMovesFromDraftToSubmitted() {
    when(db.queryForObject(startsWith("select count(*)"), eq(Integer.class), eq(driverId))).thenReturn(1);
    when(db.queryForList(contains("select distinct type"), eq(String.class), eq(driverId)))
        .thenReturn(DriverOnboardingController.REQUIRED_DOCUMENTS);
    when(db.queryForObject(eq("select kyc_status from drivers where id=?"), eq(String.class), eq(driverId))).thenReturn("SUBMITTED");

    var response = controller().submit();

    assertEquals(200, response.getStatusCode().value());
    assertEquals("SUBMITTED", response.getBody().get("kycStatus"));
    verify(db).update(contains("kyc_status in ('DRAFT','REJECTED')"), eq(driverId));
  }
}
