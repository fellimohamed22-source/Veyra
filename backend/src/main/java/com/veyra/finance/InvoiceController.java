package com.veyra.finance;

import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import org.springframework.http.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.time.YearMonth;
import java.time.format.DateTimeParseException;
import java.util.*;

/**
 * Invoice access for each party (see {@link InvoiceService}). The apps ask
 * for a short-lived link and open it in the browser, which shows the PDF.
 */
@RestController
@RequestMapping("/api/v1")
public class InvoiceController {
  private final JdbcTemplate db;
  private final InvoiceService invoices;

  public InvoiceController(JdbcTemplate db, InvoiceService invoices) {
    this.db = db;
    this.invoices = invoices;
  }

  public record Vat(Boolean vatRegistered, String vatNumber) {}

  // ------------------------------------------------------------ customer

  /** Ride invoice of the caller's completed booking (also finance/support). */
  @PostMapping("/bookings/{bookingId}/invoice/link")
  public Map<String, Object> rideLink(@PathVariable UUID bookingId) {
    boolean staff = CurrentUser.hasRole("FINANCE") || CurrentUser.hasRole("ADMIN") || CurrentUser.hasRole("SUPPORT");
    Integer mine = db.queryForObject(
        "select count(*) from scheduled_bookings sb left join drivers d on d.id=sb.selected_driver_id " +
        "left join partner_users pu on pu.partner_id=sb.partner_id and pu.user_id=? " +
        "where sb.id=? and (sb.creator_user_id=? or d.user_id=? or pu.id is not null)",
        Integer.class, CurrentUser.id(), bookingId, CurrentUser.id(), CurrentUser.id());
    if (!staff && (mine == null || mine == 0)) throw new ApiException(HttpStatus.NOT_FOUND, "BOOKING_NOT_FOUND");
    return linkOf(invoices.rideInvoice(bookingId));
  }

  // ------------------------------------------------------------ driver

  /** Driver invoices: completed rides (12 months) and monthly commissions. */
  @GetMapping("/driver/invoices")
  public Map<String, Object> driverInvoices() {
    UUID driver = driver();
    Map<String, Object> out = new LinkedHashMap<>();
    out.put("vat", vatStatus(driver));
    out.put("rides", db.queryForList(
        "select sb.id as booking_id," + InvoiceService.COMPLETED_AT_SQL + " as completed_at,sb.pickup_address,sb.dropoff_address,sb.payment_method," +
        "f.customer_total_amount_minor as total_minor,f.currency,i.number " +
        "from scheduled_bookings sb join booking_financial_snapshots f on f.booking_id=sb.id left join invoices i on i.booking_id=sb.id " +
        "where sb.selected_driver_id=? and sb.status in ('COMPLETED','CLOSED') and sb.payment_method<>'PARTNER_INVOICE' " +
        "and sb.scheduled_at>now()-interval '12 months' order by completed_at desc limit 100", driver));
    List<Map<String, Object>> months = new ArrayList<>();
    YearMonth current = YearMonth.now(InvoiceService.PARIS);
    for (int back = 0; back < 12; back++) {
      YearMonth m = current.minusMonths(back);
      Map<String, Object> sum = invoices.monthCommission(driver, m);
      if (((Number) sum.get("rides")).longValue() == 0) continue;
      Map<String, Object> row = new LinkedHashMap<>();
      row.put("month", m.toString());
      row.put("rides", sum.get("rides"));
      row.put("commissionMinor", sum.get("commission"));
      row.put("currency", sum.get("currency"));
      row.put("available", m.isBefore(current));
      row.put("number", db.queryForList("select number from invoices where kind='COMMISSION' and driver_id=? and period_start=?", String.class, driver, m.atDay(1))
          .stream().findFirst().orElse(null));
      months.add(row);
    }
    out.put("commissions", months);
    return out;
  }

  @PostMapping("/driver/invoices/rides/{bookingId}/link")
  public Map<String, Object> driverRideLink(@PathVariable UUID bookingId) {
    Integer own = db.queryForObject("select count(*) from scheduled_bookings where id=? and selected_driver_id=?", Integer.class, bookingId, driver());
    if (own == null || own == 0) throw new ApiException(HttpStatus.NOT_FOUND, "BOOKING_NOT_FOUND");
    return linkOf(invoices.rideInvoice(bookingId));
  }

  @PostMapping("/driver/invoices/commissions/{month}/link")
  public Map<String, Object> driverCommissionLink(@PathVariable String month) {
    return linkOf(invoices.commissionInvoice(driver(), month(month)));
  }

  /** VAT status of an independent driver (affiliated: set by the company). */
  @PutMapping("/driver/invoices/vat")
  public Map<String, Object> driverVat(@RequestBody Vat v) {
    UUID driver = driver();
    Integer affiliated = db.queryForObject("select count(*) from company_affiliations where driver_id=? and status='ACTIVE'", Integer.class, driver);
    if (affiliated != null && affiliated > 0) throw new ApiException(HttpStatus.CONFLICT, "VAT_MANAGED_BY_COMPANY");
    String number = vatNumber(v);
    db.update("insert into driver_companies(driver_id,vat_registered,vat_number) values (?,?,?) " +
        "on conflict(driver_id) do update set vat_registered=excluded.vat_registered,vat_number=excluded.vat_number", driver, v.vatRegistered(), number);
    return vatStatus(driver);
  }

  // ------------------------------------------------------------ company

  @PutMapping("/company/{companyId}/vat")
  public Map<String, Object> companyVat(@PathVariable UUID companyId, @RequestBody Vat v) {
    Integer member = db.queryForObject("select count(*) from company_members where company_id=? and user_id=? and status='ACTIVE'", Integer.class, companyId, CurrentUser.id());
    if (member == null || member == 0) throw new ApiException(HttpStatus.NOT_FOUND, "COMPANY_NOT_FOUND");
    db.update("update vtc_companies set vat_registered=?,vat_number=?,updated_at=now() where id=?", v.vatRegistered(), vatNumber(v), companyId);
    return db.queryForMap("select vat_registered,vat_number from vtc_companies where id=?", companyId);
  }

  // ------------------------------------------------------------ finance

  @GetMapping("/finance/invoices")
  @PreAuthorize("hasAnyRole('FINANCE','ADMIN')")
  public List<Map<String, Object>> financeList(@RequestParam(required = false) UUID driverId, @RequestParam(required = false) String kind) {
    return db.queryForList(
        "select i.id,i.kind,i.number,i.issued_at,i.booking_id,i.driver_id,i.period_start,i.total_ttc_minor,i.currency,i.seller->>'name' as seller_name,i.buyer->>'name' as buyer_name " +
        "from invoices i where (cast(? as uuid) is null or i.driver_id=?) and (cast(? as varchar) is null or i.kind=?) order by i.issued_at desc limit 200",
        driverId, driverId, kind, kind);
  }

  @PostMapping("/finance/invoices/{id}/link")
  @PreAuthorize("hasAnyRole('FINANCE','ADMIN')")
  public Map<String, Object> financeLink(@PathVariable UUID id) {
    return linkOf(invoices.byId(id));
  }

  // ------------------------------------------------------------ download

  /** PDF behind a link from one of the endpoints above (no session needed). */
  @GetMapping("/guest/invoices/{token}")
  public ResponseEntity<byte[]> download(@PathVariable String token) {
    Map<String, Object> inv = invoices.byId(invoices.fromToken(token));
    return ResponseEntity.ok()
        .contentType(MediaType.APPLICATION_PDF)
        .header(HttpHeaders.CONTENT_DISPOSITION, ContentDisposition.inline().filename(InvoiceService.filename(inv)).build().toString())
        .header(HttpHeaders.CACHE_CONTROL, "no-store")
        .body(invoices.pdf(inv));
  }

  // ------------------------------------------------------------ helpers

  private Map<String, Object> linkOf(Map<String, Object> inv) {
    Map<String, Object> out = new LinkedHashMap<>();
    out.put("id", inv.get("id"));
    out.put("number", inv.get("number"));
    out.put("url", invoices.link((UUID) inv.get("id")));
    return out;
  }

  private Map<String, Object> vatStatus(UUID driver) {
    List<Map<String, Object>> company = db.queryForList(
        "select c.legal_name,c.vat_registered,c.vat_number from company_affiliations a join vtc_companies c on c.id=a.company_id where a.driver_id=? and a.status='ACTIVE' limit 1", driver);
    Map<String, Object> out = new LinkedHashMap<>();
    if (!company.isEmpty()) {
      out.put("managedByCompany", company.getFirst().get("legal_name"));
      out.put("vatRegistered", company.getFirst().get("vat_registered"));
      out.put("vatNumber", company.getFirst().get("vat_number"));
      return out;
    }
    List<Map<String, Object>> own = db.queryForList("select vat_registered,vat_number from driver_companies where driver_id=?", driver);
    out.put("managedByCompany", null);
    out.put("vatRegistered", own.isEmpty() ? null : own.getFirst().get("vat_registered"));
    out.put("vatNumber", own.isEmpty() ? null : own.getFirst().get("vat_number"));
    return out;
  }

  private static String vatNumber(Vat v) {
    if (v == null || v.vatRegistered() == null) throw new ApiException(HttpStatus.BAD_REQUEST, "VAT_STATUS_REQUIRED");
    if (!v.vatRegistered()) return null;
    String n = v.vatNumber() == null ? "" : v.vatNumber().toUpperCase(Locale.ROOT).replaceAll("\\s", "");
    if (!n.matches("[A-Z]{2}[A-Z0-9]{2,13}")) throw new ApiException(HttpStatus.BAD_REQUEST, "VAT_NUMBER_INVALID");
    return n;
  }

  private static YearMonth month(String raw) {
    try { return YearMonth.parse(raw); } catch (DateTimeParseException e) { throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_MONTH"); }
  }

  private UUID driver() {
    List<UUID> ids = db.queryForList("select id from drivers where user_id=?", UUID.class, CurrentUser.id());
    if (ids.isEmpty()) throw new ApiException(HttpStatus.FORBIDDEN, "DRIVER_PROFILE_REQUIRED");
    return ids.getFirst();
  }
}
