package com.veyra.finance;

import com.veyra.security.PinCrypto;
import com.veyra.shared.ApiException;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;

import java.nio.charset.StandardCharsets;
import java.time.*;
import java.util.*;

import static org.junit.jupiter.api.Assertions.*;

/** Ride and commission invoices on real PostgreSQL (V059). */
@EnabledIfEnvironmentVariable(named = "TEST_DATABASE_URL", matches = ".+")
class InvoiceDatabaseTest {
  static JdbcTemplate db;
  final PinCrypto crypto = new PinCrypto("test-key-0123456789abcdef0123456");
  final InvoiceService service = new InvoiceService(db, crypto, "VEYRA", "SAS", "123456782", "1 rue de la Paix, 75002 Paris", "", 2000);
  final UUID client = UUID.randomUUID(), driverUser = UUID.randomUUID(), driver = UUID.randomUUID(), booking = UUID.randomUUID();
  final YearMonth lastMonth = YearMonth.now(InvoiceService.PARIS).minusMonths(1);

  @BeforeAll static void connect() {
    var ds = new DriverManagerDataSource(System.getenv("TEST_DATABASE_URL"), System.getenv("TEST_DATABASE_USER"), System.getenv("TEST_DATABASE_PASSWORD"));
    Flyway.configure().dataSource(ds).load().migrate();
    db = new JdbcTemplate(ds);
  }

  @BeforeEach void seed() {
    db.update("insert into users(id,first_name,last_name,email,password_hash) values (?,?,?,?,?)", client, "Marie", "Curie", client + "@example.test", "unused");
    db.update("insert into users(id,first_name,last_name,email,password_hash,account_type) values (?,?,?,?,?,'DRIVER')", driverUser, "Jean", "Dupont", driverUser + "@example.test", "unused");
    db.update("insert into drivers(id,user_id) values (?,?)", driver, driverUser);
    OffsetDateTime when = lastMonth.atDay(10).atTime(9, 0).atZone(InvoiceService.PARIS).toOffsetDateTime();
    db.update("insert into scheduled_bookings(id,creator_type,creator_user_id,pickup,pickup_address,dropoff,dropoff_address,scheduled_at,category_id,payment_method,payer_type,status,selected_driver_id) " +
        "select ?,'CLIENT',?,ST_SetSRID(ST_MakePoint(7.26,43.7),4326),'Nice',ST_SetSRID(ST_MakePoint(7.42,43.73),4326),'Monaco',?,id,'CASH','CLIENT','COMPLETED',? from vehicle_categories where code='STANDARD'",
        booking, client, when, driver);
    UUID offer = UUID.randomUUID();
    db.update("insert into driver_offers(id,booking_id,driver_id,proposed_amount_minor,currency,status) values (?,?,?,10000,'EUR','ACCEPTED')", offer, booking, driver);
    db.update("insert into booking_financial_snapshots select ?,?,id,1000,10000,1000,11000,10000,'EUR','CASH' from commission_policy_versions where scope_type='STANDARD' limit 1", booking, offer);
  }

  String code(Runnable r) { return assertThrows(ApiException.class, r::run).code(); }

  @Test void rideInvoiceNeedsTheIssuerDetailsThenIsIssuedOnce() {
    assertEquals("INVOICE_ISSUER_INCOMPLETE", code(() -> service.rideInvoice(booking)));
    db.update("insert into driver_companies(driver_id,siren,legal_name,address) values (?,?,?,?)", driver, "123456782", "Jean Dupont EI", "2 avenue Foch, Nice");
    assertEquals("INVOICE_VAT_STATUS_MISSING", code(() -> service.rideInvoice(booking)));
    db.update("update driver_companies set vat_registered=false where driver_id=?", driver);

    Map<String, Object> inv = service.rideInvoice(booking);
    assertEquals("RIDE", inv.get("kind"));
    assertEquals("F-" + LocalDate.now(InvoiceService.PARIS).getYear() + "-00001", inv.get("number"));
    assertEquals(11000L, ((Number) inv.get("total_ttc_minor")).longValue(), "the customer's total, fee included");
    assertEquals(0L, ((Number) inv.get("vat_minor")).longValue());
    assertEquals(InvoiceService.FRANCHISE_MENTION, inv.get("vat_mention"));
    assertEquals(inv.get("id"), service.rideInvoice(booking).get("id"), "issued once, then frozen");

    // Later changes to the driver's details do not alter the issued invoice.
    db.update("update driver_companies set legal_name='Autre nom' where driver_id=?", driver);
    String pdf = new String(service.pdf(service.byId((UUID) inv.get("id"))), StandardCharsets.ISO_8859_1);
    assertTrue(pdf.startsWith("%PDF"));
    assertTrue(pdf.contains("Jean Dupont EI"));
    assertTrue(pdf.contains("Marie Curie"));
  }

  @Test void vatRegisteredIssuerChargesTenPercent() {
    db.update("insert into driver_companies(driver_id,siren,legal_name,vat_registered,vat_number) values (?,?,?,true,?)", driver, "123456782", "Dupont VTC SAS", "FR40123456782");
    Map<String, Object> inv = service.rideInvoice(booking);
    assertEquals(1000, inv.get("vat_rate_bps"));
    assertEquals(10000L, ((Number) inv.get("total_ht_minor")).longValue());
    assertEquals(1000L, ((Number) inv.get("vat_minor")).longValue());
    assertNull(inv.get("vat_mention"));
  }

  @Test void unfinishedOrPartnerRidesHaveNoRideInvoice() {
    db.update("update scheduled_bookings set status='CONFIRMED' where id=?", booking);
    assertEquals("INVOICE_RIDE_NOT_COMPLETED", code(() -> service.rideInvoice(booking)));
    db.update("update scheduled_bookings set status='COMPLETED',payment_method='PARTNER_INVOICE' where id=?", booking);
    assertEquals("INVOICE_VIA_PARTNER_BILLING", code(() -> service.rideInvoice(booking)));
  }

  @Test void monthlyCommissionInvoiceForAClosedMonth() {
    db.update("insert into driver_companies(driver_id,siren,legal_name,vat_registered) values (?,?,?,false)", driver, "123456782", "Jean Dupont EI");
    assertEquals("INVOICE_PERIOD_NOT_CLOSED", code(() -> service.commissionInvoice(driver, YearMonth.now(InvoiceService.PARIS))));
    assertEquals("INVOICE_NO_RIDES", code(() -> service.commissionInvoice(driver, lastMonth.minusMonths(1))));
    InvoiceService unconfigured = new InvoiceService(db, crypto, "VEYRA", "", "", "", "", 2000);
    assertEquals("INVOICE_ISSUER_NOT_CONFIGURED", code(() -> unconfigured.commissionInvoice(driver, lastMonth)));

    Map<String, Object> inv = service.commissionInvoice(driver, lastMonth);
    assertEquals("COMMISSION", inv.get("kind"));
    assertTrue(inv.get("number").toString().matches("VC-\\d{4}-\\d{5}"));
    assertEquals(1000L, ((Number) inv.get("total_ttc_minor")).longValue());
    assertEquals(833L, ((Number) inv.get("total_ht_minor")).longValue());
    assertEquals(inv.get("id"), service.commissionInvoice(driver, lastMonth).get("id"));
  }

  @Test void linksOpenTheIssuedInvoice() {
    db.update("insert into driver_companies(driver_id,siren,vat_registered) values (?,?,false)", driver, "123456782");
    UUID id = (UUID) service.rideInvoice(booking).get("id");
    String url = service.link(id);
    assertEquals(id, service.fromToken(url.substring(url.lastIndexOf('/') + 1)));
  }
}
