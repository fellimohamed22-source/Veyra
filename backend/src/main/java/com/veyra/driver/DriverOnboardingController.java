package com.veyra.driver;

import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

import java.time.*;
import java.util.*;

/**
 * Driver KYC dossier (DR-AUTH-01..09, board 08 B). Every write is scoped
 * to the calling driver's own row; the dossier stays a draft until the
 * driver submits it from the summary step.
 */
@RestController @RequestMapping("/api/v1/driver/onboarding")
public class DriverOnboardingController {
  private final JdbcTemplate db;
  public DriverOnboardingController(JdbcTemplate d) { db = d; }

  public record Company(String siren, String siret, String legalName, String legalForm, String address) {
    public Company(String siren, String siret, String legalName) { this(siren, siret, legalName, null, null); }
  }
  public record Vtc(String registrationNumber, String cardNumber, LocalDate issuedAt, LocalDate expiresAt) {}
  public record Vehicle(UUID categoryId, String brand, String model, int year, String plateNumber, String color, Integer seats, Integer baggageCapacity) {
    public Vehicle(UUID categoryId, String brand, String model, int year, String plateNumber, String color) {
      this(categoryId, brand, model, year, plateNumber, color, null, null);
    }
  }
  public record Profile(LocalDate birthDate, String driverType) {}
  public record License(String licenseNumber, String category, LocalDate expiresAt) {}

  static final Set<String> LICENSE_CATEGORIES = Set.of("B", "BE", "C1", "D1", "D");
  static final List<String> REQUIRED_DOCUMENTS = List.of("IDENTITY", "VTC_CARD", "DRIVING_LICENSE", "INSURANCE", "VEHICLE_REGISTRATION");

  @PutMapping("/company")
  void company(@RequestBody Company c) {
    UUID d = driver();
    db.update("insert into driver_companies(driver_id,siren,siret,legal_name,legal_form,address) values (?,?,?,?,?,?) "
        + "on conflict(driver_id) do update set siren=excluded.siren,siret=excluded.siret,legal_name=excluded.legal_name,"
        + "legal_form=coalesce(excluded.legal_form,driver_companies.legal_form),address=coalesce(excluded.address,driver_companies.address)",
        d, c.siren(), c.siret(), c.legalName(), c.legalForm(), c.address());
  }

  @PutMapping("/vtc")
  void vtc(@RequestBody Vtc v) {
    UUID d = driver();
    db.update("insert into driver_vtc_registrations(driver_id,registration_number,card_number,issued_at,expires_at) values (?,?,?,?,?) on conflict(driver_id) do update set registration_number=excluded.registration_number,card_number=excluded.card_number,issued_at=excluded.issued_at,expires_at=excluded.expires_at",
        d, v.registrationNumber(), v.cardNumber(), v.issuedAt(), v.expiresAt());
  }

  @PostMapping("/vehicles")
  Map<String, UUID> vehicle(@RequestBody Vehicle v) {
    if (v.seats() != null && (v.seats() < 1 || v.seats() > 9)) throw new ApiException(HttpStatus.BAD_REQUEST, "VEHICLE_SEATS_INVALID");
    if (v.baggageCapacity() != null && (v.baggageCapacity() < 0 || v.baggageCapacity() > 20)) throw new ApiException(HttpStatus.BAD_REQUEST, "VEHICLE_BAGGAGE_INVALID");
    UUID id = UUID.randomUUID();
    db.update("insert into vehicles(id,driver_id,category_id,brand,model,year,plate_number,color,seats,baggage_capacity) values (?,?,?,?,?,?,?,?,?,?)",
        id, driver(), v.categoryId(), v.brand(), v.model(), v.year(), v.plateNumber(), v.color(), v.seats(), v.baggageCapacity());
    return Map.of("vehicleId", id);
  }

  @PutMapping("/profile")
  void profile(@RequestBody Profile p) {
    if (p.birthDate() != null && (p.birthDate().isAfter(LocalDate.now().minusYears(18)) || p.birthDate().isBefore(LocalDate.of(1900, 1, 1))))
      throw new ApiException(HttpStatus.BAD_REQUEST, "BIRTH_DATE_INVALID");
    String type = p.driverType() == null ? null : p.driverType().toUpperCase(Locale.ROOT);
    if (type != null && !Set.of("INDEPENDENT", "AFFILIATED").contains(type)) throw new ApiException(HttpStatus.BAD_REQUEST, "DRIVER_TYPE_INVALID");
    db.update("update drivers set birth_date=coalesce(?,birth_date),driver_type=coalesce(?,driver_type) where id=?", p.birthDate(), type, driver());
  }

  @PutMapping("/license")
  void license(@RequestBody License l) {
    if (l.licenseNumber() == null || l.licenseNumber().isBlank()) throw new ApiException(HttpStatus.BAD_REQUEST, "LICENSE_NUMBER_REQUIRED");
    String category = l.category() == null ? "" : l.category().toUpperCase(Locale.ROOT);
    if (!LICENSE_CATEGORIES.contains(category)) throw new ApiException(HttpStatus.BAD_REQUEST, "LICENSE_CATEGORY_INVALID");
    if (l.expiresAt() != null && l.expiresAt().isBefore(LocalDate.now())) throw new ApiException(HttpStatus.BAD_REQUEST, "LICENSE_EXPIRED");
    db.update("insert into driver_licenses(driver_id,license_number,category,expires_at) values (?,?,?,?) on conflict(driver_id) do update set license_number=excluded.license_number,category=excluded.category,expires_at=excluded.expires_at,updated_at=now()",
        driver(), l.licenseNumber().trim(), category, l.expiresAt());
  }

  /** Items the summary step requires before the dossier can be submitted. */
  List<String> missing(UUID d) {
    List<String> missing = new ArrayList<>();
    if (count("select count(*) from drivers where id=? and birth_date is not null", d) == 0) missing.add("BIRTH_DATE");
    Set<String> docs = new HashSet<>(db.queryForList("select distinct type from driver_documents where driver_id=? and status<>'SUPERSEDED'", String.class, d));
    for (String type : REQUIRED_DOCUMENTS) {
      if (!docs.contains(type)) missing.add(type);
    }
    if (count("select count(*) from driver_licenses where driver_id=?", d) == 0) missing.add("LICENSE");
    if (count("select count(*) from driver_vtc_registrations where driver_id=?", d) == 0) missing.add("VTC");
    if (count("select count(*) from driver_companies where driver_id=? and coalesce(siren,siret) is not null", d) == 0) missing.add("COMPANY");
    if (count("select count(*) from vehicles where driver_id=?", d) == 0) missing.add("VEHICLE");
    return missing;
  }

  /** « Envoyer mon dossier » (board 08 B9): draft or rejected -> submitted. */
  @PostMapping("/submit")
  ResponseEntity<Map<String, Object>> submit() {
    UUID d = driver();
    List<String> missing = missing(d);
    if (!missing.isEmpty()) return ResponseEntity.unprocessableEntity().body(Map.of("code", "DOSSIER_INCOMPLETE", "missing", missing));
    db.update("update drivers set kyc_status='SUBMITTED' where id=? and kyc_status in ('DRAFT','REJECTED')", d);
    return ResponseEntity.ok(Map.of("kycStatus", db.queryForObject("select kyc_status from drivers where id=?", String.class, d)));
  }

  @GetMapping("/status")
  Map<String, Object> status() {
    UUID d = driver();
    Map<String, Object> result = new LinkedHashMap<>(db.queryForMap("select status,kyc_status,marketplace_enabled,rating,birth_date,driver_type from drivers where id=?", d));
    result.put("documents", db.queryForList("select id,type,side,subtype,status,rejection_reason_code,created_at,expires_at from driver_documents where driver_id=? and status<>'SUPERSEDED' order by created_at desc", d));
    result.put("vehicles", db.queryForList("select v.id,v.category_id,v.brand,v.model,v.year,v.plate_number,v.color,v.seats,v.baggage_capacity,v.status,vc.display_name as category_name from vehicles v join vehicle_categories vc on vc.id=v.category_id where v.driver_id=? order by case when v.status='APPROVED' then 0 else 1 end,v.id", d));
    result.put("company", db.queryForList("select legal_name,siren,siret,legal_form,address,status from driver_companies where driver_id=?", d));
    result.put("registration", db.queryForList("select registration_number,card_number,issued_at,expires_at from driver_vtc_registrations where driver_id=?", d));
    result.put("license", db.queryForList("select license_number,category,expires_at from driver_licenses where driver_id=?", d));
    result.put("missing", missing(d));
    return result;
  }

  private int count(String sql, UUID d) {
    Integer n = db.queryForObject(sql, Integer.class, d);
    return n == null ? 0 : n;
  }

  private UUID driver() { return db.queryForObject("select id from drivers where user_id=?", UUID.class, CurrentUser.id()); }
}
