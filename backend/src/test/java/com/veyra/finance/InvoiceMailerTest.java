package com.veyra.finance;

import com.veyra.shared.ApiException;
import jakarta.mail.Multipart;
import jakarta.mail.Session;
import jakarta.mail.internet.MimeMessage;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.support.StaticListableBeanFactory;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mail.javamail.JavaMailSender;

import java.time.OffsetDateTime;
import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/** Ride invoice e-mail: PDF attached, retried when the invoice cannot be issued yet. */
class InvoiceMailerTest {
  final JdbcTemplate db = mock(JdbcTemplate.class);
  final InvoiceService invoices = mock(InvoiceService.class);
  final JavaMailSender sender = mock(JavaMailSender.class);
  final InvoiceMailer mailer = new InvoiceMailer(db, invoices, new StaticListableBeanFactory().getBeanProvider(JavaMailSender.class), "factures@veyra.test");
  final UUID booking = UUID.randomUUID();

  @Test
  void sendsTheInvoicePdfToTheCustomer() throws Exception {
    when(sender.createMimeMessage()).thenReturn(new MimeMessage((Session) null));
    Map<String, Object> inv = new HashMap<>();
    inv.put("number", "F-2026-00001");
    inv.put("issued_at", OffsetDateTime.parse("2026-10-23T10:00:00Z"));
    inv.put("total_ttc_minor", 6500L);
    inv.put("currency", "EUR");
    when(invoices.rideInvoice(booking)).thenReturn(inv);
    when(invoices.pdf(inv)).thenReturn("%PDF-1.4 test".getBytes());
    when(db.queryForMap(anyString(), eq(booking))).thenReturn(Map.of("email", "marie@example.test", "first_name", "Marie"));

    mailer.send(sender, booking);

    ArgumentCaptor<MimeMessage> sent = ArgumentCaptor.forClass(MimeMessage.class);
    verify(sender).send(sent.capture());
    MimeMessage m = sent.getValue();
    m.saveChanges();
    assertEquals("marie@example.test", m.getAllRecipients()[0].toString());
    assertEquals("factures@veyra.test", m.getFrom()[0].toString());
    assertTrue(m.getSubject().contains("F-2026-00001"));
    Multipart parts = (Multipart) m.getContent();
    boolean pdf = false;
    for (int i = 0; i < parts.getCount(); i++) pdf |= "facture-F-2026-00001.pdf".equals(parts.getBodyPart(i).getFileName());
    assertTrue(pdf, "PDF attached");
    verify(db).update(contains("ride_invoice_mails"), eq(booking), isNull(), eq(true));
  }

  @Test
  void anInvoiceThatCannotBeIssuedYetIsRetriedLater() {
    when(invoices.rideInvoice(booking)).thenThrow(new ApiException(HttpStatus.CONFLICT, "INVOICE_VAT_STATUS_MISSING"));
    mailer.send(sender, booking);
    verify(sender, never()).send(any(MimeMessage.class));
    verify(db).update(contains("next_attempt_at"), eq(booking), eq("INVOICE_VAT_STATUS_MISSING"), eq(false));
  }

  @Test
  void bodyNamesTheInvoiceAndTheAmount() {
    String body = InvoiceMailer.body("Marie", Map.of("number", "F-2026-00001", "issued_at", OffsetDateTime.parse("2026-10-23T10:00:00Z"), "total_ttc_minor", 6500L, "currency", "EUR"));
    assertTrue(body.startsWith("Bonjour Marie,"));
    assertTrue(body.contains("F-2026-00001 du 23/10/2026"));
    assertTrue(body.contains("65,00 € TTC"));
  }
}
