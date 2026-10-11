package com.veyra.booking;

import com.veyra.finance.LedgerService;
import com.veyra.security.PinCrypto;
import com.veyra.shared.ApiException;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.context.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.*;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.EnableTransactionManagement;

import javax.sql.DataSource;
import java.util.*;
import java.util.concurrent.*;
import static org.junit.jupiter.api.Assertions.*;

// Real migrations, PostgreSQL row locks, and Spring transaction proxies.
// CI supplies an isolated database; no simulated JdbcTemplate or ledger.
@EnabledIfEnvironmentVariable(named="TEST_DATABASE_URL", matches=".+")
class BookingDatabaseTest {
  static AnnotationConfigApplicationContext context;
  static JdbcTemplate db;
  static BookingController controller;
  final UUID user=UUID.randomUUID(), driver=UUID.randomUUID(), booking=UUID.randomUUID();

  @Configuration @EnableTransactionManagement(proxyTargetClass=true)
  static class Config {
    @Bean DataSource dataSource() {
      var ds=new DriverManagerDataSource(System.getenv("TEST_DATABASE_URL"),
          System.getenv("TEST_DATABASE_USER"),System.getenv("TEST_DATABASE_PASSWORD"));
      Flyway.configure().dataSource(ds).load().migrate();
      return ds;
    }
    @Bean JdbcTemplate jdbcTemplate(DataSource ds) { return new JdbcTemplate(ds); }
    @Bean PlatformTransactionManager transactionManager(DataSource ds) { return new DataSourceTransactionManager(ds); }
    @Bean LedgerService ledger(JdbcTemplate db) { return new LedgerService(db); }
    @Bean BookingController controller(JdbcTemplate db, LedgerService ledger) {
      return new BookingController(db,new BCryptPasswordEncoder(4),new PinCrypto("test-only-key"),
          ledger,120,24,60,30,new BookingStatusHistoryService(db));
    }
  }
  @BeforeAll static void connect() {
    context=new AnnotationConfigApplicationContext(Config.class);
    db=context.getBean(JdbcTemplate.class);
    controller=context.getBean(BookingController.class);
  }
  @AfterAll static void close() { if(context!=null) context.close(); }
  @BeforeEach void seed() {
    db.update("insert into users(id,first_name,email,password_hash) values (?,?,?,?)",user,"Test",user+"@example.test","unused");
    db.update("insert into drivers(id,user_id) values (?,?)",driver,user);
    db.update("insert into scheduled_bookings(id,creator_type,creator_user_id,pickup,pickup_address,dropoff,dropoff_address,scheduled_at,category_id,payment_method,payer_type,status,selected_driver_id,pin_hash) " +
        "select ?,'CLIENT',?,ST_SetSRID(ST_MakePoint(2,48),4326),'A',ST_SetSRID(ST_MakePoint(3,49),4326),'B',now()+interval '1 day',id,'CASH','CLIENT','DRIVER_ARRIVED',?,? from vehicle_categories where code='STANDARD'",
        booking,user,driver,new BCryptPasswordEncoder(4).encode("0427"));
    authenticate();
  }
  @AfterEach void clearSecurity() { SecurityContextHolder.clearContext(); }
  void authenticate() { SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(user,null)); }
  String status() { return db.queryForObject("select status from scheduled_bookings where id=?",String.class,booking); }
  int count(String table) { return db.queryForObject("select count(*) from "+table+" where booking_id=?",Integer.class,booking); }
  void snapshot(String method) {
    UUID offer=UUID.randomUUID();
    db.update("insert into driver_offers(id,booking_id,driver_id,proposed_amount_minor,currency,status) values (?,?,?,10000,'EUR','ACCEPTED')",offer,booking,driver);
    db.update("insert into booking_financial_snapshots select ?,?,id,1000,10000,1000,11000,10000,'EUR',? from commission_policy_versions where scope_type='STANDARD' limit 1",booking,offer,method);
  }
  @Test void failedPinCommitsAttemptsAndLockButDoesNotAdvanceRide() {
    for(int i=1;i<=5;i++) {
      assertThrows(ApiException.class,()->controller.start(booking,new BookingController.Pin("9999")));
      assertEquals(i,db.queryForObject("select pin_failed_attempts from scheduled_bookings where id=?",Integer.class,booking));
    }
    assertEquals("PIN_TEMPORARILY_LOCKED",assertThrows(ApiException.class,
        ()->controller.start(booking,new BookingController.Pin("0427"))).code());
    assertEquals("DRIVER_ARRIVED",status());
    assertEquals(0,count("booking_status_history"));
  }
  @Test void competingStartsAdvanceOnlyOnce() throws Exception {
    assertEquals(List.of("OK","INVALID_BOOKING_TRANSITION"),race(()->controller.start(booking,new BookingController.Pin("0427"))));
    assertEquals("IN_PROGRESS",status());
    assertEquals(1,count("booking_status_history"));
  }
  @ParameterizedTest @ValueSource(strings={"CASH","ONLINE","PARTNER_INVOICE"})
  void competingCompletionsSettleOnlyOnce(String method) throws Exception {
    snapshot(method);
    db.update("update scheduled_bookings set status='IN_PROGRESS',payment_method=? where id=?",method,booking);
    assertEquals(List.of("OK","INVALID_BOOKING_TRANSITION"),race(()->controller.complete(booking)));
    assertEquals("COMPLETED",status());
    assertEquals(method.equals("CASH")?1:0,count("driver_platform_debts"));
    assertEquals(method.equals("CASH")?0:1,count("driver_payables"));
    assertEquals(1,count("ledger_transactions"));
    assertEquals(1,count("booking_status_history"));
    assertEquals(method.equals("CASH")?2:3,db.queryForObject("select count(*) from ledger_entries e join ledger_transactions t on t.id=e.transaction_id where t.booking_id=?",Integer.class,booking));
    assertEquals(0L,db.queryForObject("select sum(case when e.direction='DEBIT' then e.amount_minor else -e.amount_minor end) from ledger_entries e join ledger_transactions t on t.id=e.transaction_id where t.booking_id=?",Long.class,booking));
  }
  @Test void onlineStartRequiresCapturedPaymentInDatabase() {
    db.update("update scheduled_bookings set payment_method='ONLINE' where id=?",booking);
    assertEquals("PAYMENT_REQUIRED",assertThrows(ApiException.class,
        ()->controller.start(booking,new BookingController.Pin("0427"))).code());
    assertEquals("DRIVER_ARRIVED",status());
    db.update("insert into payments(booking_id,payer_user_id,amount_minor,currency,method,status,idempotency_key) values (?,?,11000,'EUR','ONLINE','CAPTURED',?)",booking,user,booking.toString());
    controller.start(booking,new BookingController.Pin("0427"));
    assertEquals("IN_PROGRESS",status());
    assertEquals(1,count("booking_status_history"));
  }
  @ParameterizedTest @ValueSource(strings={"CASH","ONLINE","PARTNER_INVOICE"})
  void zeroCommissionPolicyStillAllowsCompletion(String method) {
    snapshot(method);
    db.update("update booking_financial_snapshots set commission_rate_bps=0,platform_commission_amount_minor=0,customer_total_amount_minor=10000 where booking_id=?",booking);
    db.update("update scheduled_bookings set status='IN_PROGRESS',payment_method=? where id=?",method,booking);
    controller.complete(booking);
    assertEquals("COMPLETED",status());
    assertEquals(1,count("booking_status_history"));
    assertEquals(0,count("driver_platform_debts"));
    assertEquals(method.equals("CASH")?0:1,count("driver_payables"));
    assertEquals(method.equals("CASH")?0:1,count("ledger_transactions"));
    if(!method.equals("CASH")) {
      assertEquals(2,db.queryForObject("select count(*) from ledger_entries e join ledger_transactions t on t.id=e.transaction_id where t.booking_id=?",Integer.class,booking));
      assertEquals(0L,db.queryForObject("select sum(case when e.direction='DEBIT' then e.amount_minor else -e.amount_minor end) from ledger_entries e join ledger_transactions t on t.id=e.transaction_id where t.booking_id=?",Long.class,booking));
    }
  }
  @Test void missingFinancialSnapshotRollsBackCompletionAndNotifications() {
    db.update("update scheduled_bookings set status='IN_PROGRESS' where id=?",booking);
    assertThrows(ApiException.class,()->controller.complete(booking));
    assertEquals("IN_PROGRESS",status());
    assertEquals(0,count("booking_status_history"));
    assertEquals(0,count("driver_platform_debts"));
    assertEquals(0,db.queryForObject("select count(*) from outbox_events where aggregate_id=?",Integer.class,booking));
  }
  @Test void bookingDetailUsesTheSameDeterministicVehicleAsOfferCards() {
    for(String plate:List.of("A-"+booking.toString().substring(0,12),"B-"+booking.toString().substring(0,12))) {
      db.update("insert into vehicles(driver_id,category_id,brand,model,year,plate_number,status) select ?,id,'Test','Car',2024,?,'APPROVED' from vehicle_categories where code='STANDARD'",driver,plate);
    }
    String expected=db.queryForObject("select plate_number from vehicles where driver_id=? order by id limit 1",String.class,driver);
    var detail=new BookingQueryController(db).detail(booking);
    assertEquals(expected,detail.get("plate_number"));
    assertEquals("Standard",detail.get("category_name"));
    var driverDetail=new com.veyra.driver.DriverBookingController(db).detail(booking);
    assertEquals(expected,driverDetail.get("plate_number"));
    assertEquals(detail.get("vehicle_brand"),driverDetail.get("vehicle_brand"));
    assertEquals(detail.get("vehicle_model"),driverDetail.get("vehicle_model"));
    assertEquals(false,detail.get("driver_verified"));
    db.update("update drivers set kyc_status='APPROVED' where id=?",driver);
    assertEquals(true,new BookingQueryController(db).detail(booking).get("driver_verified"));
    db.update("update drivers set kyc_status='REJECTED' where id=?",driver);
    assertEquals(false,new BookingQueryController(db).detail(booking).get("driver_verified"));
  }
  UUID activeOffer(UUID bookingId) {
    UUID offer=UUID.randomUUID();
    db.update("insert into driver_offers(id,booking_id,driver_id,proposed_amount_minor,currency,status,expires_at) values (?,?,?,10000,'EUR','ACTIVE',now()+interval '1 hour')",offer,bookingId,driver);
    return offer;
  }
  UUID prepareSelection() {
    db.update("update drivers set status='ACTIVE',kyc_status='APPROVED',marketplace_enabled=true where id=?",driver);
    db.update("insert into vehicles(driver_id,category_id,brand,model,year,plate_number,status) select ?,id,'Test','Car',2024,?,'APPROVED' from vehicle_categories where code='STANDARD'",driver,booking.toString().substring(0,16));
    db.update("update scheduled_bookings set status='OFFERS_RECEIVED',selected_driver_id=null,offer_window_ends_at=now()+interval '1 hour' where id=?",booking);
    return activeOffer(booking);
  }
  @Test void marketReferenceIgnoresOwnAndExpiredOffersWithoutInventingAPrice() {
    prepareSelection();
    db.update("update scheduled_bookings set offer_visibility_mode='BEST_VISIBLE' where id=?",booking);
    UUID otherUser=UUID.randomUUID(),otherDriver=UUID.randomUUID();
    db.update("insert into users(id,first_name,email,password_hash) values (?,'Other',?,'unused')",otherUser,otherUser+"@example.test");
    db.update("insert into drivers(id,user_id) values (?,?)",otherDriver,otherUser);
    UUID current=UUID.randomUUID();
    db.update("insert into driver_offers(id,booking_id,driver_id,proposed_amount_minor,currency,status,expires_at) values (?,?,?,500,'EUR','ACTIVE',now()-interval '1 minute')",current,booking,otherDriver);
    var query=new com.veyra.driver.DriverOpportunityController(db);
    assertNull(query.detail(booking).get("currentBestOtherOfferMinor"));
    db.update("update driver_offers set proposed_amount_minor=12000,expires_at=now()+interval '1 hour' where id=?",current);
    assertEquals(12000L,query.detail(booking).get("currentBestOtherOfferMinor"));
    assertEquals(10000L,query.detail(booking).get("ownActiveOfferAmountMinor"));
    db.update("update driver_offers set status='WITHDRAWN' where id=?",current);
    assertNull(query.detail(booking).get("currentBestOtherOfferMinor"));
  }
  @ParameterizedTest @ValueSource(strings={"driver","kyc","marketplace","vehicle","category","expiry","window","booking"})
  void offerCountsMatchSelectableOffersAfterEligibilityChanges(String change) {
    UUID offer=prepareSelection();
    assertOfferCounts(1);
    switch(change) {
      case "driver" -> db.update("update drivers set status='INACTIVE' where id=?",driver);
      case "kyc" -> db.update("update drivers set kyc_status='REJECTED' where id=?",driver);
      case "marketplace" -> db.update("update drivers set marketplace_enabled=false where id=?",driver);
      case "vehicle" -> db.update("update vehicles set status='REJECTED' where driver_id=?",driver);
      case "category" -> db.update("update vehicles set category_id=(select id from vehicle_categories where code='VAN') where driver_id=?",driver);
      case "expiry" -> db.update("update driver_offers set expires_at=now()-interval '1 minute' where id=?",offer);
      case "window" -> db.update("update scheduled_bookings set offer_window_ends_at=now()-interval '1 minute' where id=?",booking);
      case "booking" -> db.update("update scheduled_bookings set status='CONFIRMED' where id=?",booking);
    }
    assertOfferCounts(0);
  }
  void assertOfferCounts(int expected) {
    assertEquals(expected,controller.ownerOffers(booking).size());
    assertEquals(expected,((Number)controller.mine(null,"desc",null).getFirst().get("offer_count")).intValue());
    assertEquals(expected,((Number)new BookingQueryController(db).detail(booking).get("offer_count")).intValue());
  }
  @Test void concurrentPublicationCreatesOneOpenRequestVisibleToEligibleDriver() throws Exception {
    prepareSelection();
    UUID category=db.queryForObject("select id from vehicle_categories where code='STANDARD'",UUID.class);
    String pickup="Nice-"+booking;
    var request=new BookingDtos.Create(new BookingDtos.Point(43.7,7.2,pickup),
        new BookingDtos.Point(43.5,7.0,"Cannes"),java.time.OffsetDateTime.now().plusHours(5),
        category,"CASH","CLIENT",null,null,null,2,1,"Siège enfant",null);
    String key="publication-"+booking;
    assertEquals(List.of("OK","OK"),race(()->controller.createIdempotently(request,key)));
    UUID created=db.queryForObject("select booking_id from booking_creation_requests where user_id=? and request_key=?",UUID.class,user,key);
    assertEquals(1,db.queryForObject("select count(*) from scheduled_bookings where creator_user_id=? and pickup_address=?",Integer.class,user,pickup));
    assertEquals(1,db.queryForObject("select count(*) from outbox_events where aggregate_id=? and event_type='booking.published'",Integer.class,created));
    var detail=new BookingQueryController(db).detail(created);
    assertEquals("OPEN_FOR_OFFERS",detail.get("status"));
    assertEquals(2,detail.get("passenger_count"));
    assertEquals(1,detail.get("baggage_count"));
    assertEquals("Siège enfant",detail.get("customer_notes"));
    assertNull(detail.get("selected_driver_id"));
    var visible=controller.opportunities("date",category,null,null,null,pickup,null,null);
    assertEquals(1,visible.size());
    assertEquals(created,visible.getFirst().get("id"));
    assertEquals(created,controller.createIdempotently(request,key).getBody().get("id"));
    db.update("update drivers set marketplace_enabled=false where id=?",driver);
    assertEquals("DRIVER_NOT_ELIGIBLE",assertThrows(ApiException.class,
        ()->controller.opportunities("date",category,null,null,null,pickup,null,null)).code());
  }
  @Test void selectionCreatesSnapshotAndJourneyCanComplete() {
    UUID offer=prepareSelection();
    var accepted=controller.accept(booking,offer);
    assertEquals(11000L,accepted.get("totalMinor"));
    assertEquals(10000L,accepted.get("driverNetMinor"));
    assertEquals(1,count("booking_financial_snapshots"));
    String encrypted=db.queryForObject("select pin_encrypted from scheduled_bookings where id=?",String.class,booking);
    String pin=new PinCrypto("test-only-key").decrypt(encrypted);
    controller.enroute(booking); controller.arrived(booking);
    controller.start(booking,new BookingController.Pin(pin)); controller.complete(booking);
    assertEquals("COMPLETED",status());
    assertEquals(5,count("booking_status_history"));
    assertEquals(1,count("ledger_transactions"));
  }
  @Test void competingSelectionsDoNotDuplicateSnapshot() throws Exception {
    UUID offer=prepareSelection();
    assertEquals(List.of("OK","BOOKING_CLOSED"),race(()->controller.accept(booking,offer)));
    assertEquals(1,count("booking_financial_snapshots"));
    assertEquals(1,count("booking_status_history"));
  }
  @Test void oneDriverCannotBeAssignedOverlappingBookingsConcurrently() throws Exception {
    UUID offer=prepareSelection(), otherBooking=UUID.randomUUID();
    db.update("insert into scheduled_bookings(id,creator_type,creator_user_id,pickup,pickup_address,dropoff,dropoff_address,scheduled_at,category_id,payment_method,payer_type,status,offer_window_ends_at) select ?,creator_type,creator_user_id,pickup,pickup_address,dropoff,dropoff_address,scheduled_at,category_id,payment_method,payer_type,'OFFERS_RECEIVED',offer_window_ends_at from scheduled_bookings where id=?",otherBooking,booking);
    UUID otherOffer=activeOffer(otherBooking);
    assertEquals(List.of("OK","DRIVER_SCHEDULE_CONFLICT"),race(()->controller.accept(booking,offer),()->controller.accept(otherBooking,otherOffer)));
    assertEquals(1,db.queryForObject("select count(*) from scheduled_bookings where id in (?,?) and status='CONFIRMED'",Integer.class,booking,otherBooking));
    assertEquals(1,db.queryForObject("select count(*) from booking_financial_snapshots where booking_id in (?,?)",Integer.class,booking,otherBooking));
  }
  @Test void expiredOfferCannotBeChosenFromAnOldScreen() {
    UUID offer=prepareSelection();
    db.update("update driver_offers set expires_at=now()-interval '1 second' where id=?",offer);
    assertEquals("OFFER_CLOSED",assertThrows(ApiException.class,()->controller.accept(booking,offer)).code());
    assertEquals("OFFERS_RECEIVED",status());
    assertEquals(0,count("booking_financial_snapshots"));
  }
  @ParameterizedTest @ValueSource(strings={"inactive","kyc","marketplace","vehicle","category"})
  void selectionRechecksEligibilityAndApprovedVehicle(String revoked) {
    UUID offer=prepareSelection();
    switch(revoked) {
      case "inactive" -> db.update("update drivers set status='SUSPENDED' where id=?",driver);
      case "kyc" -> db.update("update drivers set kyc_status='REJECTED' where id=?",driver);
      case "marketplace" -> db.update("update drivers set marketplace_enabled=false where id=?",driver);
      case "vehicle" -> db.update("update vehicles set status='REJECTED' where driver_id=?",driver);
      case "category" -> db.update("update vehicles set category_id=(select id from vehicle_categories where code='VAN') where driver_id=?",driver);
    }
    assertEquals("OFFER_CLOSED",assertThrows(ApiException.class,()->controller.accept(booking,offer)).code());
    assertEquals("OFFERS_RECEIVED",status());
    assertEquals(0,count("booking_financial_snapshots"));
  }
  void seedFilterRows(List<String> states) {
    db.update("update scheduled_bookings set status='DRAFT' where id=?",booking);
    int hours=0;
    for(String state:states) {
      db.update("insert into scheduled_bookings(id,creator_type,creator_user_id,pickup,pickup_address,dropoff,dropoff_address,scheduled_at,category_id,payment_method,payer_type,status,selected_driver_id) select ?,creator_type,creator_user_id,pickup,pickup_address,dropoff,dropoff_address,scheduled_at+(?::integer)*interval '1 hour',category_id,payment_method,payer_type,?,selected_driver_id from scheduled_bookings where id=?",UUID.randomUUID(),++hours,state,booking);
    }
  }
  @Test void customerFiltersAllStatusesAndSortsAcrossPages() {
    var states=List.of("OPEN_FOR_OFFERS","OFFERS_RECEIVED","CONFIRMED","DRIVER_EN_ROUTE","DRIVER_ARRIVED","IN_PROGRESS","COMPLETED","CLOSED","CANCELLED","DRIVER_CANCELLED","CUSTOMER_NO_SHOW","EXPIRED","NO_OFFER");
    seedFilterRows(states);
    for(String state:states) {
      var rows=controller.mine(state,"asc",0);
      assertEquals(1,rows.size(),state);
      assertEquals(state,rows.getFirst().get("status"));
    }
    var ascending=controller.mine(null,"asc",null);
    var descending=controller.mine(null,"desc",null);
    assertEquals(14,ascending.size());
    var expected=new ArrayList<>(ascending.stream().map(row->row.get("id")).toList());
    Collections.reverse(expected);
    assertEquals(expected,descending.stream().map(row->row.get("id")).toList());
    var first=controller.mine(null,"desc",0);
    var second=controller.mine(null,"desc",1);
    assertEquals(10,first.size()); assertEquals(4,second.size());
    var paged=new ArrayList<>(first);paged.addAll(second);
    assertEquals(descending.stream().map(row->row.get("id")).toList(),paged.stream().map(row->row.get("id")).toList());
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(UUID.randomUUID(),null));
    assertTrue(controller.mine(null,"asc",null).isEmpty());
  }
  @Test void driverAllScopeFiltersExactlyEachOperationalAndHistoricalStatus() {
    var states=List.of("CONFIRMED","DRIVER_EN_ROUTE","DRIVER_ARRIVED","IN_PROGRESS","COMPLETED","CLOSED","CANCELLED","DRIVER_CANCELLED","CUSTOMER_NO_SHOW");
    seedFilterRows(states);
    var query=new com.veyra.driver.DriverBookingController(db);
    for(String state:states) {
      var rows=query.mine("all",state,"asc",0);
      assertEquals(1,rows.size(),state);
      assertEquals(state,rows.getFirst().get("status"));
      assertEquals("Standard",rows.getFirst().get("category_name"));
    }
    var ascending=query.mine("all",null,"asc",0);
    var descending=query.mine("all",null,"desc",0);
    assertEquals(9,ascending.size());
    var expected=new ArrayList<>(ascending.stream().map(row->row.get("id")).toList());
    Collections.reverse(expected);
    assertEquals(expected,descending.stream().map(row->row.get("id")).toList());
  }
  List<String> race(Runnable action) throws Exception { return race(action,action); }
  List<String> race(Runnable firstAction,Runnable secondAction) throws Exception {
    var ready=new CountDownLatch(2);
    var go=new CountDownLatch(1);
    try(var pool=Executors.newFixedThreadPool(2)) {
      java.util.function.Function<Runnable,Callable<String>> task=action->()->{
        authenticate();
        try {
          ready.countDown();
          assertTrue(go.await(10,TimeUnit.SECONDS));
          try { action.run(); return "OK"; } catch(ApiException e) { return e.code(); }
        } finally { SecurityContextHolder.clearContext(); }
      };
      var first=pool.submit(task.apply(firstAction)); var second=pool.submit(task.apply(secondAction));
      assertTrue(ready.await(10,TimeUnit.SECONDS)); go.countDown();
      var results=new ArrayList<>(List.of(first.get(20,TimeUnit.SECONDS),second.get(20,TimeUnit.SECONDS)));
      results.sort(Comparator.reverseOrder());
      return results;
    } finally { go.countDown(); }
  }
}
