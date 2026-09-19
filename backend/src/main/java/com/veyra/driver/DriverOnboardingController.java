package com.veyra.driver;

import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;
import java.util.*;

@RestController
@RequestMapping("/api/v1/driver/onboarding")
public class DriverOnboardingController {
  private final JdbcTemplate db;

  public DriverOnboardingController(JdbcTemplate db) {
    this.db = db;
  }

  public record Company(String siren, String siret, String legalName) {}
  public record Vtc(String registrationNumber, String cardNumber, LocalDate issuedAt, LocalDate expiresAt) {}
  public record Vehicle(UUID categoryId, String brand, String model, int year, String plateNumber, String color) {}

  @PutMapping("/company")
  void company(@RequestBody Company company) {
    UUID driverId = driver();
    db.update(
        "insert into driver_companies(driver_id,siren,siret,legal_name) values (?,?,?,?) " +
        "on conflict(driver_id) do update set siren=excluded.siren,siret=excluded.siret,legal_name=excluded.legal_name",
        driverId, company.siren(), company.siret(), company.legalName());
  }

  @PutMapping("/vtc")
  void vtc(@RequestBody Vtc vtc) {
    UUID driverId = driver();
    db.update(
        "insert into driver_vtc_registrations(driver_id,registration_number,card_number,issued_at,expires_at) values (?,?,?,?,?) " +
        "on conflict(driver_id) do update set registration_number=excluded.registration_number,card_number=excluded.card_number,issued_at=excluded.issued_at,expires_at=excluded.expires_at",
        driverId, vtc.registrationNumber(), vtc.cardNumber(), vtc.issuedAt(), vtc.expiresAt());
  }

  @PostMapping("/vehicles")
  Map<String, UUID> vehicle(@RequestBody Vehicle vehicle) {
    UUID id = UUID.randomUUID();
    db.update(
        "insert into vehicles(id,driver_id,category_id,brand,model,year,plate_number,color) values (?,?,?,?,?,?,?,?)",
        id, driver(), vehicle.categoryId(), vehicle.brand(), vehicle.model(), vehicle.year(),
        vehicle.plateNumber(), vehicle.color());
    return Map.of("vehicleId", id);
  }

  @GetMapping("/status")
  Map<String, Object> status() {
    UUID driverId = driver();
    Map<String,Object> result=new LinkedHashMap<>(db.queryForMap(
        "select status,kyc_status,marketplace_enabled,rating from drivers where id=?",
        driverId));
    result.put("documents",db.queryForList(
        "select id,type,status,original_filename,expires_at,rejection_reason_code,created_at from driver_documents where driver_id=? order by created_at desc",
        driverId));
    result.put("vehicles",db.queryForList(
        "select id,brand,model,year,plate_number,color,status from vehicles where driver_id=? order by created_at desc",
        driverId));
    return result;
  }

  private UUID driver() {
    List<UUID> ids = db.queryForList(
        "select id from drivers where user_id=?",
        UUID.class, CurrentUser.id());
    if (ids.isEmpty()) {
      // This endpoint is also used during startup. A missing profile is an
      // expected onboarding state, not an INTERNAL_ERROR caused by
      // EmptyResultDataAccessException.
      throw new ApiException(HttpStatus.CONFLICT, "DRIVER_PROFILE_REQUIRED");
    }
    return ids.getFirst();
  }
}
