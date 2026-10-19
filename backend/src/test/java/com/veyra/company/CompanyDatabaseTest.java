package com.veyra.company;

import com.veyra.booking.BookingController;
import com.veyra.shared.ApiException;
import com.veyra.storage.FileStorageProvider;
import com.veyra.storage.StoredFile;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.support.StaticListableBeanFactory;
import org.springframework.context.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.*;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.EnableTransactionManagement;

import javax.sql.DataSource;
import java.io.*;
import java.time.LocalDate;
import java.util.*;

import static org.junit.jupiter.api.Assertions.*;

/**
 * VTC company flows on real PostgreSQL (SOC-01..10, DR-AFF): creation,
 * invitation code, attachment validation with vehicle assignment, fleet
 * marketplace rules (company approval, expired vehicle papers), and the
 * affiliated driver's onboarding checklist.
 */
@EnabledIfEnvironmentVariable(named = "TEST_DATABASE_URL", matches = ".+")
class CompanyDatabaseTest {
  static AnnotationConfigApplicationContext context;
  static JdbcTemplate db;
  static CompanyController company;
  static DriverCompanyController driverSide;

  final UUID owner = UUID.randomUUID(), driverUser = UUID.randomUUID(), driver = UUID.randomUUID(), outsider = UUID.randomUUID();
  // Valid SIREN (Luhn) unique per test run.
  final String siren = siren();

  @Configuration
  @EnableTransactionManagement(proxyTargetClass = true)
  static class Config {
    @Bean DataSource dataSource() {
      var ds = new DriverManagerDataSource(System.getenv("TEST_DATABASE_URL"), System.getenv("TEST_DATABASE_USER"), System.getenv("TEST_DATABASE_PASSWORD"));
      Flyway.configure().dataSource(ds).load().migrate();
      return ds;
    }
    @Bean JdbcTemplate jdbcTemplate(DataSource ds) { return new JdbcTemplate(ds); }
    @Bean PlatformTransactionManager transactionManager(DataSource ds) { return new DataSourceTransactionManager(ds); }
    @Bean FileStorageProvider storage() {
      return new FileStorageProvider() {
        public StoredFile store(InputStream c, String n, String t, long s) { return new StoredFile("mem/" + UUID.randomUUID(), n, t, s); }
        public InputStream load(String k) { return new ByteArrayInputStream(new byte[0]); }
        public void delete(String k) {}
        public boolean exists(String k) { return true; }
      };
    }
    @Bean CompanyController company(JdbcTemplate db, FileStorageProvider s) {
      return new CompanyController(db, s, new StaticListableBeanFactory().getBeanProvider(JavaMailSender.class));
    }
    @Bean DriverCompanyController driverSide(JdbcTemplate db) { return new DriverCompanyController(db); }
  }

  @BeforeAll static void connect() {
    context = new AnnotationConfigApplicationContext(Config.class);
    db = context.getBean(JdbcTemplate.class);
    company = context.getBean(CompanyController.class);
    driverSide = context.getBean(DriverCompanyController.class);
  }
  @AfterAll static void close() { if (context != null) context.close(); }

  @BeforeEach void seed() {
    for (UUID u : List.of(owner, driverUser, outsider))
      db.update("insert into users(id,first_name,last_name,email,password_hash) values (?,?,?,?,?)", u, "Test", "Martin", u + "@example.test", "unused");
    db.update("insert into drivers(id,user_id) values (?,?)", driver, driverUser);
    as(owner);
  }
  @AfterEach void clear() { SecurityContextHolder.clearContext(); }

  void as(UUID u) { SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(u, null)); }

  static String siren() {
    Random r = new Random();
    while (true) {
      String s = String.format("%09d", Math.abs(r.nextLong()) % 1_000_000_000L);
      if (CompanyController.luhn(s)) return s;
    }
  }

  UUID createCompany() {
    var body = company.create(new CompanyController.CompanyForm("Transports Prestige", siren, "EVTC075230145", "12 rue de Rivoli, 75001 Paris", "contact@prestige.test")).getBody();
    return (UUID) body.get("id");
  }

  UUID addVehicle(UUID c) {
    UUID category = db.queryForObject("select id from vehicle_categories where code='STANDARD'", UUID.class);
    String plate = "T" + UUID.randomUUID().toString().substring(0, 8).toUpperCase();
    return (UUID) company.addVehicle(c, new CompanyController.VehicleForm(category, "Mercedes", "Classe E", 2023, plate, "Noir", 4, 3)).getBody().get("id");
  }

  boolean usable(UUID vehicle) {
    return db.queryForObject("select count(*) from vehicles v where v.id=? and " + FleetRules.usable("v"), Integer.class, vehicle) == 1;
  }

  @Test void ownerCreatesACompanyAndGetsTheRoleAndAnInvitationCode() {
    UUID c = createCompany();
    Map<String, Object> o = company.overview(c);
    assertEquals("DRAFT", o.get("status"));
    assertTrue(((String) o.get("invite_code")).matches("TRAN-[A-Z2-9]{4}"));
    assertEquals(1, db.queryForObject("select count(*) from user_roles ur join roles r on r.id=ur.role_id where ur.user_id=? and r.code='COMPANY_OWNER'", Integer.class, owner));
    assertThrows(ApiException.class, this::createCompany, "one company per owner");
  }

  @Test void invalidSirenIsRefused() {
    var e = assertThrows(ApiException.class, () -> company.create(new CompanyController.CompanyForm("X", "123456789", null, null, null)));
    assertEquals("SIREN_INVALID", e.code());
  }

  @Test void outsidersCannotSeeTheCompany() {
    UUID c = createCompany();
    as(outsider);
    assertThrows(AccessDeniedException.class, () -> company.overview(c));
    assertThrows(AccessDeniedException.class, () -> company.drivers(c));
  }

  @Test void submissionListsMissingDocumentsThenSucceeds() throws IOException {
    UUID c = createCompany();
    var refused = company.submit(c);
    assertEquals(422, refused.getStatusCode().value());
    assertTrue(((List<?>) refused.getBody().get("missing")).containsAll(List.of("KBIS", "REVTC_CERTIFICATE", "RC_INSURANCE", "VEHICLE")));
    for (String t : CompanyController.REQUIRED_COMPANY_DOCUMENTS)
      company.upload(c, t, new MockMultipartFile("file", t + ".pdf", "application/pdf", new byte[]{1}), null, LocalDate.now().plusYears(1));
    addVehicle(c);
    assertEquals(200, company.submit(c).getStatusCode().value());
    assertEquals("SUBMITTED", db.queryForObject("select status from vtc_companies where id=?", String.class, c));
  }

  @Test void driverJoinsWithTheCodeAndTheCompanyValidatesAndAssignsAVehicle() {
    UUID c = createCompany();
    UUID vehicle = addVehicle(c);
    String code = (String) company.overview(c).get("invite_code");

    as(driverUser);
    var joined = driverSide.join(new DriverCompanyController.Join(code.toLowerCase().replace("-", "")));
    assertEquals("PENDING", joined.getBody().get("status"));
    assertEquals("AFFILIATED", db.queryForObject("select driver_type from drivers where id=?", String.class, driver));
    assertEquals("AFFILIATION_EXISTS", assertThrows(ApiException.class, () -> driverSide.join(new DriverCompanyController.Join(code))).code());

    as(owner);
    UUID affiliation = (UUID) company.drivers(c).getFirst().get("affiliation_id");
    // A pending driver cannot receive a vehicle yet.
    assertEquals("DRIVER_NOT_AFFILIATED", assertThrows(ApiException.class, () -> company.assign(c, vehicle, new CompanyController.Assignment(driver))).code());
    company.approve(c, affiliation, new CompanyController.Approval(vehicle));
    assertEquals(driver, db.queryForObject("select driver_id from vehicles where id=?", UUID.class, vehicle));

    as(driverUser);
    Map<String, Object> mine = driverSide.current();
    assertEquals("ACTIVE", mine.get("status"));
    assertEquals(1, ((List<?>) mine.get("vehicles")).size());

    as(owner);
    company.end(c, affiliation);
    assertNull(db.queryForObject("select driver_id from vehicles where id=?", UUID.class, vehicle), "vehicle taken back");
  }

  @Test void unknownCodeIsRefused() {
    as(driverUser);
    assertEquals("INVITE_CODE_INVALID", assertThrows(ApiException.class, () -> driverSide.join(new DriverCompanyController.Join("ZZZZ-9999"))).code());
  }

  @Test void fleetVehicleIsUsableOnlyWhileTheCompanyIsApprovedAndItsPapersAreValid() {
    UUID c = createCompany();
    UUID vehicle = addVehicle(c);
    assertFalse(usable(vehicle), "draft company");
    db.update("update vtc_companies set status='APPROVED' where id=?", c);
    assertTrue(usable(vehicle));
    db.update("insert into company_documents(company_id,vehicle_id,type,storage_key,expires_at) values (?,?,'VEHICLE_INSURANCE','k',current_date-1)", c, vehicle);
    assertFalse(usable(vehicle), "expired insurance blocks the vehicle");
    db.update("update company_documents set status='SUPERSEDED' where vehicle_id=?", vehicle);
    assertTrue(usable(vehicle));
    db.update("update vtc_companies set status='SUSPENDED' where id=?", c);
    assertFalse(usable(vehicle), "suspended company");
  }

  @Test void expiringDocumentsAppearInTheDashboard() {
    UUID c = createCompany();
    UUID vehicle = addVehicle(c);
    db.update("insert into company_documents(company_id,vehicle_id,type,storage_key,expires_at) values (?,?,'VEHICLE_INSURANCE','k',current_date+6)", c, vehicle);
    db.update("insert into company_documents(company_id,type,storage_key,expires_at) values (?,'KBIS','k',current_date+200)", c);
    List<Map<String, Object>> due = company.expiriesList(c);
    assertEquals(1, due.size());
    assertEquals("VEHICLE", due.getFirst().get("scope"));
    assertEquals(1L, ((Number) company.overview(c).get("documentsToRenew")).longValue());
  }

  @Test void expiredDriverDocumentIsDetected() {
    db.update("insert into driver_documents(driver_id,type,storage_key,status,expires_at) values (?,'VTC_CARD','k','APPROVED',current_date-2)", driver);
    assertEquals(1, db.queryForObject(FleetRules.DRIVER_DOCUMENT_EXPIRED_SQL, Integer.class, driver));
  }

  @Test void eligibleVehicleSqlStillCompilesWithFleetRules() {
    // Guards the concatenation used by offers and the dashboard.
    assertNotNull(db.queryForObject("select count(*) from scheduled_bookings sb where " + BookingController.ELIGIBLE_VEHICLE_SQL, Integer.class, driver));
  }
}
