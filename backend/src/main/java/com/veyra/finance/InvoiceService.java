package com.veyra.finance;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.veyra.security.PinCrypto;
import com.veyra.shared.ApiException;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.time.*;
import java.time.format.DateTimeFormatter;
import java.util.*;

/**
 * Ride and commission invoices (owner decision 22/10/2026, V059).
 * <ul>
 * <li>RIDE: issued by VEYRA in the name and on behalf of the ride's issuer
 * (independent driver, or the VTC company of an affiliated driver) to the
 * customer, for the total the customer paid. VAT 10 % (passenger transport)
 * when the issuer is VAT-registered, otherwise the art. 293 B mention.</li>
 * <li>COMMISSION: VEYRA invoices each driver, per closed month, the platform
 * commission of that month's completed rides.</li>
 * </ul>
 * Invoices are issued on first request and then frozen (snapshots).
 */
@Service
public class InvoiceService {
  static final ZoneId PARIS = ZoneId.of("Europe/Paris");
  static final int RIDE_VAT_BPS = 1000;
  static final String FRANCHISE_MENTION = "TVA non applicable, art. 293 B du CGI";
  static final String COMPLETED_AT_SQL = "coalesce((select max(h.created_at) from booking_status_history h where h.booking_id=sb.id and h.to_status='COMPLETED'),sb.scheduled_at)";
  private static final Duration LINK_TTL = Duration.ofMinutes(15);
  private static final DateTimeFormatter DAY = DateTimeFormatter.ofPattern("dd/MM/yyyy");
  private static final DateTimeFormatter DAY_TIME = DateTimeFormatter.ofPattern("dd/MM/yyyy 'à' HH:mm");

  private final JdbcTemplate db;
  private final PinCrypto crypto;
  private final ObjectMapper json = new ObjectMapper();
  private final Map<String, String> veyra;
  private final int commissionVatBps;

  public InvoiceService(JdbcTemplate db, PinCrypto crypto,
      @Value("${veyra.invoice.issuer-name:VEYRA}") String name,
      @Value("${veyra.invoice.issuer-legal-form:}") String legalForm,
      @Value("${veyra.invoice.issuer-siren:}") String siren,
      @Value("${veyra.invoice.issuer-address:}") String address,
      @Value("${veyra.invoice.issuer-vat-number:}") String vatNumber,
      @Value("${veyra.invoice.commission-vat-bps:2000}") int commissionVatBps) {
    this.db = db;
    this.crypto = crypto;
    Map<String, String> v = new LinkedHashMap<>();
    v.put("name", name);
    v.put("legalForm", legalForm);
    v.put("siren", siren);
    v.put("address", address);
    v.put("vatNumber", vatNumber);
    this.veyra = Collections.unmodifiableMap(v);
    this.commissionVatBps = commissionVatBps;
  }

  // ------------------------------------------------------------ issuing

  /** Ride invoice of a completed booking, issued on first call. */
  @Transactional
  public Map<String, Object> rideInvoice(UUID bookingId) {
    List<Map<String, Object>> existing = db.queryForList("select * from invoices where booking_id=?", bookingId);
    if (!existing.isEmpty()) return existing.getFirst();
    List<Map<String, Object>> rows = db.queryForList(
        "select sb.id,sb.status,sb.payment_method,sb.pickup_address,sb.dropoff_address,sb.selected_driver_id," + COMPLETED_AT_SQL + " as completed_at," +
        "u.first_name,u.last_name,u.email,f.customer_total_amount_minor,f.currency " +
        "from scheduled_bookings sb join users u on u.id=sb.creator_user_id " +
        "left join booking_financial_snapshots f on f.booking_id=sb.id where sb.id=?", bookingId);
    if (rows.isEmpty()) throw new ApiException(HttpStatus.NOT_FOUND, "BOOKING_NOT_FOUND");
    Map<String, Object> b = rows.getFirst();
    if (!Set.of("COMPLETED", "CLOSED").contains((String) b.get("status"))) throw new ApiException(HttpStatus.CONFLICT, "INVOICE_RIDE_NOT_COMPLETED");
    if ("PARTNER_INVOICE".equals(b.get("payment_method"))) throw new ApiException(HttpStatus.CONFLICT, "INVOICE_VIA_PARTNER_BILLING");
    if (b.get("customer_total_amount_minor") == null || b.get("selected_driver_id") == null) throw new ApiException(HttpStatus.CONFLICT, "INVOICE_RIDE_NOT_COMPLETED");
    UUID driverId = (UUID) b.get("selected_driver_id");
    Issuer issuer = issuer(driverId);
    long ttc = ((Number) b.get("customer_total_amount_minor")).longValue();
    int vatBps = issuer.vatRegistered ? RIDE_VAT_BPS : 0;
    long ht = excludingVat(ttc, vatBps);
    OffsetDateTime completedAt = odt(b.get("completed_at"));
    String label = "Transport de personnes en VTC le " + completedAt.atZoneSameInstant(PARIS).format(DAY) + " : "
        + b.get("pickup_address") + " → " + b.get("dropoff_address");
    Map<String, Object> buyer = new LinkedHashMap<>();
    buyer.put("name", (Objects.toString(b.get("first_name"), "") + " " + Objects.toString(b.get("last_name"), "")).trim());
    buyer.put("email", b.get("email"));
    Map<String, Object> extra = new LinkedHashMap<>();
    extra.put("serviceAt", completedAt.toString());
    extra.put("payment", "ONLINE".equals(b.get("payment_method")) ? "ONLINE" : "CASH");
    return insert("RIDE", issuer.key, "F", bookingId, driverId, null, null, issuer.seller, buyer,
        List.of(line(label, 1, ht, vatBps, ttc)), extra, vatBps, ht, ttc - ht, ttc, (String) b.get("currency"),
        issuer.vatRegistered ? null : FRANCHISE_MENTION);
  }

  /** Commission invoice of a driver for a closed month, issued on first call. */
  @Transactional
  public Map<String, Object> commissionInvoice(UUID driverId, YearMonth month) {
    if (!month.isBefore(YearMonth.now(PARIS))) throw new ApiException(HttpStatus.CONFLICT, "INVOICE_PERIOD_NOT_CLOSED");
    List<Map<String, Object>> existing = db.queryForList("select * from invoices where kind='COMMISSION' and driver_id=? and period_start=?", driverId, month.atDay(1));
    if (!existing.isEmpty()) return existing.getFirst();
    if (veyra.get("siren").isBlank() || veyra.get("address").isBlank()) throw new ApiException(HttpStatus.CONFLICT, "INVOICE_ISSUER_NOT_CONFIGURED");
    Map<String, Object> sum = monthCommission(driverId, month);
    long rides = ((Number) sum.get("rides")).longValue();
    if (rides == 0) throw new ApiException(HttpStatus.NOT_FOUND, "INVOICE_NO_RIDES");
    long ttc = ((Number) sum.get("commission")).longValue();
    long ht = excludingVat(ttc, commissionVatBps);
    Issuer driverSide = issuer(driverId);
    Map<String, Object> seller = new LinkedHashMap<>(veyra);
    String period = month.atDay(1).format(DAY) + " au " + month.atEndOfMonth().format(DAY);
    String label = "Commission d'intermédiation VEYRA : " + rides + (rides > 1 ? " courses" : " course") + " du " + period;
    return insert("COMMISSION", "VEYRA", "VC", null, driverId, month.atDay(1), month.atEndOfMonth(), seller, driverSide.seller,
        List.of(line(label, rides, ht, commissionVatBps, ttc)), Map.of(), commissionVatBps, ht, ttc - ht, ttc, (String) sum.get("currency"), null);
  }

  Map<String, Object> monthCommission(UUID driverId, YearMonth month) {
    Instant from = month.atDay(1).atStartOfDay(PARIS).toInstant(), to = month.plusMonths(1).atDay(1).atStartOfDay(PARIS).toInstant();
    return db.queryForMap(
        "select count(*) as rides,coalesce(sum(f.platform_commission_amount_minor),0) as commission,coalesce(max(f.currency),'EUR') as currency " +
        "from scheduled_bookings sb join booking_financial_snapshots f on f.booking_id=sb.id " +
        "where sb.selected_driver_id=? and sb.status in ('COMPLETED','CLOSED') and " + COMPLETED_AT_SQL + ">=? and " + COMPLETED_AT_SQL + "<?",
        driverId, OffsetDateTime.ofInstant(from, ZoneOffset.UTC), OffsetDateTime.ofInstant(to, ZoneOffset.UTC));
  }

  private record Issuer(String key, Map<String, Object> seller, boolean vatRegistered) {}

  /** Who invoices the driver's rides: the VTC company of an affiliated driver, else the driver. */
  private Issuer issuer(UUID driverId) {
    String driverName = db.queryForObject("select trim(coalesce(u.first_name,'')||' '||coalesce(u.last_name,'')) from drivers d join users u on u.id=d.user_id where d.id=?", String.class, driverId);
    List<Map<String, Object>> company = db.queryForList(
        "select c.id,c.legal_name,c.siren,c.address,c.vat_registered,c.vat_number from company_affiliations a join vtc_companies c on c.id=a.company_id " +
        "where a.driver_id=? and a.status='ACTIVE' limit 1", driverId);
    Map<String, Object> seller = new LinkedHashMap<>();
    if (!company.isEmpty()) {
      Map<String, Object> c = company.getFirst();
      if (c.get("vat_registered") == null) throw new ApiException(HttpStatus.CONFLICT, "INVOICE_VAT_STATUS_MISSING");
      seller.put("name", c.get("legal_name"));
      seller.put("siren", c.get("siren"));
      seller.put("address", c.get("address"));
      seller.put("vatNumber", c.get("vat_number"));
      seller.put("driverName", driverName);
      return new Issuer("CMP-" + c.get("id"), seller, (Boolean) c.get("vat_registered"));
    }
    List<Map<String, Object>> own = db.queryForList("select legal_name,legal_form,siren,siret,address,vat_registered,vat_number from driver_companies where driver_id=?", driverId);
    Map<String, Object> d = own.isEmpty() ? Map.of() : own.getFirst();
    if (d.get("siren") == null && d.get("siret") == null) throw new ApiException(HttpStatus.CONFLICT, "INVOICE_ISSUER_INCOMPLETE");
    if (d.get("vat_registered") == null) throw new ApiException(HttpStatus.CONFLICT, "INVOICE_VAT_STATUS_MISSING");
    seller.put("name", d.get("legal_name") == null || d.get("legal_name").toString().isBlank() ? driverName : d.get("legal_name"));
    seller.put("legalForm", d.get("legal_form"));
    seller.put("siren", d.get("siret") != null ? d.get("siret") : d.get("siren"));
    seller.put("address", d.get("address"));
    seller.put("vatNumber", d.get("vat_number"));
    seller.put("driverName", driverName);
    return new Issuer("DRV-" + driverId, seller, (Boolean) d.get("vat_registered"));
  }

  private Map<String, Object> insert(String kind, String issuerKey, String prefix, UUID bookingId, UUID driverId, LocalDate start, LocalDate end,
      Map<String, Object> seller, Map<String, Object> buyer, List<Map<String, Object>> lines, Map<String, Object> extra,
      int vatBps, long ht, long vat, long ttc, String currency, String mention) {
    int year = LocalDate.now(PARIS).getYear();
    Integer no = db.queryForObject(
        "insert into invoice_sequences(issuer_key,year,last_no) values (?,?,1) on conflict(issuer_key,year) do update set last_no=invoice_sequences.last_no+1 returning last_no",
        Integer.class, issuerKey, year);
    String number = String.format("%s-%d-%05d", prefix, year, no);
    Map<String, Object> buyerWithExtra = new LinkedHashMap<>(buyer);
    if (!extra.isEmpty()) buyerWithExtra.put("_ride", extra);
    UUID id = UUID.randomUUID();
    db.update("insert into invoices(id,kind,issuer_key,number,booking_id,driver_id,period_start,period_end,seller,buyer,lines,vat_rate_bps,total_ht_minor,vat_minor,total_ttc_minor,currency,vat_mention) " +
        "values (?,?,?,?,?,?,?,?,?::jsonb,?::jsonb,?::jsonb,?,?,?,?,?,?)",
        id, kind, issuerKey, number, bookingId, driverId, start, end, write(seller), write(buyerWithExtra), write(lines), vatBps, ht, vat, ttc, currency, mention);
    return db.queryForMap("select * from invoices where id=?", id);
  }

  static long excludingVat(long ttc, int vatBps) {
    return Math.round(ttc * 10000d / (10000 + vatBps));
  }

  private static Map<String, Object> line(String label, long quantity, long ht, int vatBps, long ttc) {
    Map<String, Object> l = new LinkedHashMap<>();
    l.put("label", label);
    l.put("quantity", quantity);
    l.put("htMinor", ht);
    l.put("vatBps", vatBps);
    l.put("ttcMinor", ttc);
    return l;
  }

  // ------------------------------------------------------------ links

  /** Short-lived download path (authenticated by an encrypted token). */
  public String link(UUID invoiceId) {
    String token = crypto.encrypt("INV|" + invoiceId + "|" + Instant.now().plus(LINK_TTL).getEpochSecond());
    return "/api/v1/guest/invoices/" + token.replace('+', '-').replace('/', '_').replace("=", "");
  }

  public UUID fromToken(String token) {
    try {
      String std = token.replace('-', '+').replace('_', '/');
      std += "=".repeat((4 - std.length() % 4) % 4);
      String[] parts = crypto.decrypt(std).split("\\|");
      if (parts.length != 3 || !"INV".equals(parts[0])) throw new IllegalArgumentException();
      if (Instant.now().getEpochSecond() > Long.parseLong(parts[2])) throw new ApiException(HttpStatus.GONE, "INVOICE_LINK_EXPIRED");
      return UUID.fromString(parts[1]);
    } catch (ApiException e) {
      throw e;
    } catch (RuntimeException e) {
      throw new ApiException(HttpStatus.NOT_FOUND, "INVOICE_NOT_FOUND");
    }
  }

  public Map<String, Object> byId(UUID id) {
    List<Map<String, Object>> rows = db.queryForList("select * from invoices where id=?", id);
    if (rows.isEmpty()) throw new ApiException(HttpStatus.NOT_FOUND, "INVOICE_NOT_FOUND");
    return rows.getFirst();
  }

  // ------------------------------------------------------------ PDF

  public byte[] pdf(Map<String, Object> inv) {
    Map<String, Object> seller = read(inv.get("seller")), buyer = read(inv.get("buyer"));
    List<Map<String, Object>> lines = json.convertValue(readAny(inv.get("lines")), new TypeReference<>() {});
    boolean ride = "RIDE".equals(inv.get("kind"));
    String currency = Objects.toString(inv.get("currency"), "EUR");
    SimplePdf p = new SimplePdf();
    float left = 48, right = SimplePdf.WIDTH - 48;

    p.fill(0, 0, SimplePdf.WIDTH, 92, 0.063f, 0.122f, 0.235f);
    p.color(1, 1, 1).text(left, 52, 26, true, "VEYRA");
    p.text(left, 72, 9, false, ride ? "Facture de course VTC" : "Facture de commission");
    p.textRight(right, 46, 18, true, "FACTURE");
    p.textRight(right, 66, 10, false, "N° " + inv.get("number"));
    p.textRight(right, 80, 10, false, "Date : " + odt(inv.get("issued_at")).atZoneSameInstant(PARIS).format(DAY));
    p.color(0, 0, 0);

    float top = 128;
    p.text(left, top, 8, true, ride ? "PRESTATAIRE" : "ÉMETTEUR");
    p.text(310, top, 8, true, "CLIENT");
    float lt = party(p, left, top + 16, seller, ride);
    float rt = party(p, 310, top + 16, buyer, false);
    top = Math.max(lt, rt) + 10;

    if (ride) {
      top = p.paragraph(left, top, 8.5f, false, right - left,
          "Facture émise par VEYRA au nom et pour le compte de " + seller.get("name") + ", en vertu d'un mandat de facturation.");
      Map<String, Object> rideInfo = read(buyer.get("_ride"));
      if (rideInfo.get("serviceAt") != null)
        top = p.paragraph(left, top, 8.5f, false, right - left, "Date de la prestation : " + OffsetDateTime.parse(rideInfo.get("serviceAt").toString()).atZoneSameInstant(PARIS).format(DAY_TIME));
      top += 8;
    } else {
      top = p.paragraph(left, top, 8.5f, false, right - left, "Période : du " + date(inv.get("period_start")).format(DAY) + " au " + date(inv.get("period_end")).format(DAY)) + 8;
    }

    float cQty = 330, cHt = 400, cVat = 455, cTtc = right;
    p.fill(left, top, right - left, 20, 0.93f, 0.95f, 0.98f);
    p.text(left + 6, top + 13.5f, 8, true, "DÉSIGNATION");
    p.textRight(cQty, top + 13.5f, 8, true, "QTÉ");
    p.textRight(cHt, top + 13.5f, 8, true, "MONTANT HT");
    p.textRight(cVat, top + 13.5f, 8, true, "TVA");
    p.textRight(cTtc - 6, top + 13.5f, 8, true, "MONTANT TTC");
    top += 34;
    for (Map<String, Object> l : lines) {
      float lineTop = top;
      top = p.paragraph(left + 6, top, 9, false, cQty - left - 40, Objects.toString(l.get("label"), ""));
      p.textRight(cQty, lineTop, 9, false, Objects.toString(l.get("quantity"), "1"));
      p.textRight(cHt, lineTop, 9, false, money(num(l.get("htMinor")), currency));
      p.textRight(cVat, lineTop, 9, false, percent(num(l.get("vatBps"))));
      p.textRight(cTtc - 6, lineTop, 9, false, money(num(l.get("ttcMinor")), currency));
      top += 4;
      p.line(left, top, right, top, 0.85f);
      top += 16;
    }

    float labelX = 360;
    top += 6;
    p.text(labelX, top, 9.5f, false, "Total HT");
    p.textRight(cTtc - 6, top, 9.5f, false, money(num(inv.get("total_ht_minor")), currency));
    top += 16;
    p.text(labelX, top, 9.5f, false, "TVA " + percent(num(inv.get("vat_rate_bps"))));
    p.textRight(cTtc - 6, top, 9.5f, false, money(num(inv.get("vat_minor")), currency));
    top += 10;
    p.fill(labelX - 8, top, cTtc - labelX + 8, 24, 0.063f, 0.122f, 0.235f);
    p.color(1, 1, 1).text(labelX, top + 16, 11, true, "Total TTC");
    p.textRight(cTtc - 6, top + 16, 11, true, money(num(inv.get("total_ttc_minor")), currency));
    p.color(0, 0, 0);
    top += 46;

    if (inv.get("vat_mention") != null) top = p.paragraph(left, top, 9, true, right - left, inv.get("vat_mention").toString()) + 4;
    if (ride) {
      String payment = "ONLINE".equals(read(buyer.get("_ride")).get("payment")) ? "par carte bancaire en ligne" : "en espèces auprès du chauffeur";
      top = p.paragraph(left, top, 9, false, right - left, "Facture acquittée : réglée " + payment + ".");
    } else {
      top = p.paragraph(left, top, 9, false, right - left,
          "Montant prélevé sur vos gains ou réglé selon les conditions de la charte chauffeur VEYRA. "
              + "En cas de retard de paiement : pénalités au taux légal majoré et indemnité forfaitaire de 40 € pour frais de recouvrement (art. L441-10 du Code de commerce).");
    }

    p.line(left, SimplePdf.HEIGHT - 60, right, SimplePdf.HEIGHT - 60, 0.85f);
    p.paragraph(left, SimplePdf.HEIGHT - 46, 7.5f, false, right - left, footer());
    return p.toBytes();
  }

  private float party(SimplePdf p, float x, float top, Map<String, Object> who, boolean showDriver) {
    float w = 235;
    top = p.paragraph(x, top, 10, true, w, Objects.toString(who.get("name"), ""));
    for (String key : List.of("legalForm", "address", "email")) {
      Object v = who.get(key);
      if (v != null && !v.toString().isBlank()) top = p.paragraph(x, top, 9, false, w, v.toString());
    }
    Object siren = who.get("siren");
    if (siren != null && !siren.toString().isBlank()) top = p.paragraph(x, top, 9, false, w, (siren.toString().length() == 14 ? "SIRET : " : "SIREN : ") + siren);
    Object vat = who.get("vatNumber");
    if (vat != null && !vat.toString().isBlank()) top = p.paragraph(x, top, 9, false, w, "N° TVA : " + vat);
    Object driver = who.get("driverName");
    if (showDriver && driver != null && !driver.toString().isBlank() && !driver.equals(who.get("name")))
      top = p.paragraph(x, top, 9, false, w, "Chauffeur : " + driver);
    return top;
  }

  private String footer() {
    StringBuilder f = new StringBuilder(veyra.get("name"));
    if (!veyra.get("legalForm").isBlank()) f.append(" ").append(veyra.get("legalForm"));
    if (!veyra.get("siren").isBlank()) f.append(" · SIREN ").append(veyra.get("siren"));
    if (!veyra.get("address").isBlank()) f.append(" · ").append(veyra.get("address"));
    if (!veyra.get("vatNumber").isBlank()) f.append(" · TVA ").append(veyra.get("vatNumber"));
    return f.append(" · Plateforme de mise en relation VTC").toString();
  }

  static String money(long minor, String currency) {
    String sign = minor < 0 ? "-" : "";
    long a = Math.abs(minor);
    String units = String.format(Locale.ROOT, "%,d", a / 100).replace(',', ' ');
    return sign + units + "," + String.format("%02d", a % 100) + ("EUR".equals(currency) ? " €" : " " + currency);
  }

  static String percent(long bps) {
    return bps % 100 == 0 ? (bps / 100) + " %" : String.format(Locale.FRANCE, "%.2f %%", bps / 100d);
  }

  private static long num(Object o) { return o == null ? 0 : ((Number) o).longValue(); }

  private String write(Object o) {
    try { return json.writeValueAsString(o); } catch (Exception e) { throw new IllegalStateException(e); }
  }

  private Object readAny(Object o) {
    if (o == null) return null;
    try { return json.readValue(o.toString(), Object.class); } catch (Exception e) { throw new IllegalStateException(e); }
  }

  private Map<String, Object> read(Object o) {
    if (o == null) return Map.of();
    if (o instanceof Map<?, ?> m) return json.convertValue(m, new TypeReference<>() {});
    Object v = readAny(o);
    return v instanceof Map ? json.convertValue(v, new TypeReference<>() {}) : Map.of();
  }

  static OffsetDateTime odt(Object o) {
    if (o instanceof OffsetDateTime t) return t;
    if (o instanceof java.sql.Timestamp t) return t.toInstant().atOffset(ZoneOffset.UTC);
    if (o instanceof Instant i) return i.atOffset(ZoneOffset.UTC);
    return OffsetDateTime.parse(o.toString());
  }

  private static LocalDate date(Object o) {
    if (o instanceof java.sql.Date d) return d.toLocalDate();
    if (o instanceof LocalDate d) return d;
    return LocalDate.parse(o.toString());
  }

  static String filename(Map<String, Object> inv) {
    return "facture-" + new String(Objects.toString(inv.get("number")).getBytes(StandardCharsets.US_ASCII), StandardCharsets.US_ASCII) + ".pdf";
  }
}
