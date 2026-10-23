package com.veyra.finance;

import com.veyra.shared.ApiException;
import jakarta.mail.internet.MimeMessage;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.format.DateTimeFormatter;
import java.util.*;

/**
 * Sends each customer the invoice of their completed ride, PDF attached.
 * Runs apart from the ride completion so that a missing VAT status or an
 * SMTP outage never blocks the ride; failures are retried with a growing
 * delay. Only rides completed in the last 24 hours are picked up.
 */
@Component
public class InvoiceMailer {
  static final int MAX_ATTEMPTS = 48;
  private static final Logger log = LoggerFactory.getLogger(InvoiceMailer.class);
  private static final DateTimeFormatter DAY = DateTimeFormatter.ofPattern("dd/MM/yyyy");

  private final JdbcTemplate db;
  private final InvoiceService invoices;
  private final ObjectProvider<JavaMailSender> mail;
  private final String from;

  public InvoiceMailer(JdbcTemplate db, InvoiceService invoices, ObjectProvider<JavaMailSender> mail,
      @Value("${veyra.mail.from:}") String from) {
    this.db = db;
    this.invoices = invoices;
    this.mail = mail;
    this.from = from;
  }

  @Scheduled(fixedDelayString = "${veyra.invoice-mail.poll-ms:300000}", initialDelayString = "${veyra.invoice-mail.initial-delay-ms:60000}")
  public void sendPending() {
    JavaMailSender sender = mail.getIfAvailable();
    if (sender == null) return;
    List<UUID> due = db.queryForList(
        "select sb.id from scheduled_bookings sb left join ride_invoice_mails m on m.booking_id=sb.id " +
        "where sb.status in ('COMPLETED','CLOSED') and sb.payment_method<>'PARTNER_INVOICE' " +
        "and " + InvoiceService.COMPLETED_AT_SQL + ">now()-interval '24 hours' " +
        "and (m.booking_id is null or (m.sent_at is null and m.attempts<? and m.next_attempt_at<=now())) limit 20",
        UUID.class, MAX_ATTEMPTS);
    for (UUID booking : due) send(sender, booking);
  }

  void send(JavaMailSender sender, UUID booking) {
    try {
      Map<String, Object> inv = invoices.rideInvoice(booking);
      Map<String, Object> to = db.queryForMap(
          "select u.email::text as email,u.first_name from scheduled_bookings sb join users u on u.id=sb.creator_user_id where sb.id=?", booking);
      MimeMessage message = sender.createMimeMessage();
      MimeMessageHelper h = new MimeMessageHelper(message, true, "UTF-8");
      if (from != null && !from.isBlank()) h.setFrom(from);
      h.setTo(to.get("email").toString());
      h.setSubject("VEYRA — Facture de votre course " + inv.get("number"));
      h.setText(body(Objects.toString(to.get("first_name"), ""), inv));
      h.addAttachment(InvoiceService.filename(inv), new ByteArrayResource(invoices.pdf(inv)), "application/pdf");
      sender.send(message);
      record(booking, null, true);
    } catch (ApiException e) {
      record(booking, e.code(), false);
    } catch (Exception e) {
      log.warn("RIDE_INVOICE_MAIL_FAILED booking={}", booking, e);
      record(booking, "MAIL_FAILED", false);
    }
  }

  static String body(String firstName, Map<String, Object> inv) {
    String day = InvoiceService.odt(inv.get("issued_at")).atZoneSameInstant(InvoiceService.PARIS).format(DAY);
    return "Bonjour" + (firstName.isBlank() ? "" : " " + firstName) + ",\n\n"
        + "Merci d'avoir voyagé avec VEYRA. Vous trouverez ci-joint la facture n° " + inv.get("number") + " du " + day
        + ", d'un montant de " + InvoiceService.money(((Number) inv.get("total_ttc_minor")).longValue(), Objects.toString(inv.get("currency"), "EUR")) + " TTC.\n\n"
        + "Elle reste disponible dans l'application VEYRA, depuis le détail de la course.\n\n"
        + "L'équipe VEYRA";
  }

  private void record(UUID booking, String error, boolean sent) {
    db.update("insert into ride_invoice_mails(booking_id,attempts,last_error,sent_at,next_attempt_at) values (?,1,?,case when ? then now() end,now()+interval '10 minutes') " +
        "on conflict(booking_id) do update set attempts=ride_invoice_mails.attempts+1,last_error=excluded.last_error,sent_at=excluded.sent_at," +
        "next_attempt_at=now()+(ride_invoice_mails.attempts+1)*interval '10 minutes'", booking, error, sent);
  }
}
