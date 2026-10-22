package com.veyra.finance;

import com.veyra.security.PinCrypto;
import com.veyra.shared.ApiException;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;

import java.nio.charset.StandardCharsets;
import java.time.OffsetDateTime;
import java.util.*;

import static org.junit.jupiter.api.Assertions.*;

/** Invoice rendering, amounts and download links, without a database. */
class InvoicePdfTest {
  final PinCrypto crypto = new PinCrypto("test-key-0123456789abcdef0123456");
  final InvoiceService service = new InvoiceService(null, crypto, "VEYRA", "SAS", "123456782", "1 rue de la Paix, 75002 Paris", "FR40123456782", 2000);

  @Test
  void amountsSplitVatFromTheTotal() {
    assertEquals(4545, InvoiceService.excludingVat(5000, 1000));
    assertEquals(5000, InvoiceService.excludingVat(5000, 0));
    assertEquals(833, InvoiceService.excludingVat(1000, 2000));
    assertEquals("1 234,50 €", InvoiceService.money(123450, "EUR"));
    assertEquals("0,05 €", InvoiceService.money(5, "EUR"));
    assertEquals("10 %", InvoiceService.percent(1000));
    assertEquals("5,50 %", InvoiceService.percent(550));
  }

  @Test
  void rideInvoicePdfCarriesTheLegalMentions() {
    Map<String, Object> inv = new HashMap<>();
    inv.put("id", UUID.randomUUID());
    inv.put("kind", "RIDE");
    inv.put("number", "F-2026-00001");
    inv.put("issued_at", OffsetDateTime.parse("2026-10-22T10:00:00Z"));
    inv.put("seller", "{\"name\":\"Jean Dupont EI\",\"siren\":\"123456782\",\"address\":\"2 avenue Foch, Nice\",\"driverName\":\"Jean Dupont\"}");
    inv.put("buyer", "{\"name\":\"Marie Curie\",\"email\":\"marie@example.com\",\"_ride\":{\"serviceAt\":\"2026-10-21T08:30:00Z\",\"payment\":\"CASH\"}}");
    inv.put("lines", "[{\"label\":\"Transport de personnes en VTC le 21/10/2026 : Nice → Monaco\",\"quantity\":1,\"htMinor\":5000,\"vatBps\":0,\"ttcMinor\":5000}]");
    inv.put("vat_rate_bps", 0);
    inv.put("total_ht_minor", 5000L);
    inv.put("vat_minor", 0L);
    inv.put("total_ttc_minor", 5000L);
    inv.put("currency", "EUR");
    inv.put("vat_mention", InvoiceService.FRANCHISE_MENTION);
    byte[] pdf = service.pdf(inv);
    String raw = new String(pdf, StandardCharsets.ISO_8859_1);
    assertTrue(raw.startsWith("%PDF-1.4"));
    assertTrue(raw.trim().endsWith("%%EOF"));
    assertTrue(raw.contains("(F-2026-00001)") || raw.contains("F-2026-00001"));
    assertTrue(raw.contains("mandat de facturation"));
    assertTrue(raw.contains("art. 293 B du CGI"));
    // Accents and the euro sign are WinAnsi octal escapes (é = \351, € = \200).
    assertTrue(raw.contains("\\351"));
    assertTrue(raw.contains("50,00 \\200"));
    assertTrue(raw.contains("Facture acquitt\\351e"));
    int xref = Integer.parseInt(raw.substring(raw.lastIndexOf("startxref") + 10).trim().split("\\s")[0]);
    assertTrue(raw.startsWith("xref", xref), "startxref points at the xref table");
  }

  @Test
  void downloadLinksAreSignedAndExpire() {
    UUID id = UUID.randomUUID();
    String url = service.link(id);
    assertTrue(url.startsWith("/api/v1/guest/invoices/"));
    String token = url.substring(url.lastIndexOf('/') + 1);
    assertFalse(token.contains("+") || token.contains("/") || token.contains("="));
    assertEquals(id, service.fromToken(token));
    ApiException forged = assertThrows(ApiException.class, () -> service.fromToken(token.substring(0, token.length() - 3) + "abc"));
    assertEquals(HttpStatus.NOT_FOUND, forged.status());
    String expired = crypto.encrypt("INV|" + id + "|1").replace('+', '-').replace('/', '_').replace("=", "");
    assertEquals(HttpStatus.GONE, assertThrows(ApiException.class, () -> service.fromToken(expired)).status());
  }

  @Test
  void longLabelsWrapWithinTheColumn() {
    List<String> lines = SimplePdf.wrap("Transport de personnes en VTC le 21/10/2026 : 12 promenade des Anglais, 06000 Nice → Aéroport Nice Côte d'Azur Terminal 2", 9, false, 240);
    assertTrue(lines.size() > 1);
    for (String l : lines) assertTrue(SimplePdf.width(l, 9, false) <= 240 || !l.contains(" "));
  }
}
