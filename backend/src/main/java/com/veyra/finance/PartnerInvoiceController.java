package com.veyra.finance;

import com.veyra.shared.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;
import java.util.*;

@RestController
@RequestMapping("/api/v1/finance")
@PreAuthorize("hasAnyRole('FINANCE','ADMIN')")
public class PartnerInvoiceController {
  private final JdbcTemplate db;

  public PartnerInvoiceController(JdbcTemplate db){
    this.db=db;
  }

  @PostMapping("/partners/{partnerId}/invoices/generate")
  @Transactional
  public Map<String,Object> generate(
      @PathVariable UUID partnerId,
      @RequestParam LocalDate from,
      @RequestParam LocalDate to){

    if(from==null||to==null||to.isBefore(from)){
      throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"INVALID_INVOICE_PERIOD");
    }

    List<Map<String,Object>> accountRows=db.queryForList(
        "select po.status,po.credit_status,po.currency,pia.payment_terms_days,pia.status as invoice_status " +
        "from partner_organizations po join partner_invoice_accounts pia on pia.partner_id=po.id " +
        "where po.id=? for update",
        partnerId);
    if(accountRows.isEmpty()){
      throw new ApiException(HttpStatus.NOT_FOUND,"PARTNER_INVOICE_ACCOUNT_NOT_FOUND");
    }
    Map<String,Object> account=accountRows.getFirst();
    if(!"APPROVED".equals(account.get("status")) ||
        !"APPROVED".equals(account.get("credit_status")) ||
        !"ACTIVE".equals(account.get("invoice_status"))){
      throw new ApiException(HttpStatus.CONFLICT,"PARTNER_INVOICE_ACCOUNT_NOT_ACTIVE");
    }

    List<Map<String,Object>> items=new ArrayList<>();

    items.addAll(db.queryForList(
        "select sb.id as booking_id,bfs.driver_net_amount_minor as driver_net_minor," +
        "bfs.platform_commission_amount_minor as commission_minor,0::bigint as tax_minor," +
        "bfs.customer_total_amount_minor as total_minor,bfs.currency,'RIDE' as item_type " +
        "from scheduled_bookings sb join booking_financial_snapshots bfs on bfs.booking_id=sb.id " +
        "where sb.partner_id=? and sb.payment_method='PARTNER_INVOICE' " +
        "and sb.status in ('COMPLETED','CLOSED') and sb.scheduled_at::date between ? and ? " +
        "and not exists(select 1 from partner_invoice_items pii where pii.booking_id=sb.id)",
        partnerId,from,to));

    items.addAll(db.queryForList(
        "select sb.id as booking_id,cc.driver_compensation_minor as driver_net_minor," +
        "cc.platform_amount_minor as commission_minor,0::bigint as tax_minor," +
        "cc.charged_amount_minor as total_minor,cc.currency,'CANCELLATION' as item_type " +
        "from scheduled_bookings sb join cancellation_charges cc on cc.booking_id=sb.id " +
        "where sb.partner_id=? and sb.payment_method='PARTNER_INVOICE' " +
        "and sb.status in ('CANCELLED','CUSTOMER_NO_SHOW') and sb.scheduled_at::date between ? and ? " +
        "and not exists(select 1 from partner_invoice_items pii where pii.booking_id=sb.id)",
        partnerId,from,to));

    if(items.isEmpty()){
      throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"NO_INVOICE_ITEMS");
    }

    long total=items.stream()
        .mapToLong(item->((Number)item.get("total_minor")).longValue())
        .sum();

    String currency=account.get("currency")==null?"EUR":account.get("currency").toString();
    int terms=((Number)account.get("payment_terms_days")).intValue();
    UUID invoiceId=UUID.randomUUID();

    db.update(
        "insert into partner_invoices(id,partner_id,period_start,period_end,total_minor,currency,status,due_at) " +
        "values (?,?,?,?,?,?,'ISSUED',?)",
        invoiceId,partnerId,from,to,total,currency,to.plusDays(terms));

    for(Map<String,Object> item:items){
      db.update(
          "insert into partner_invoice_items(invoice_id,booking_id,driver_net_minor,commission_minor,tax_minor,total_minor) " +
          "values (?,?,?,?,?,?)",
          invoiceId,item.get("booking_id"),item.get("driver_net_minor"),
          item.get("commission_minor"),item.get("tax_minor"),item.get("total_minor"));
    }

    db.update(
        "update partner_invoice_accounts set outstanding_minor=outstanding_minor+? where partner_id=?",
        total,partnerId);

    return Map.of(
        "invoiceId",invoiceId,
        "totalMinor",total,
        "currency",currency,
        "items",items.size(),
        "status","ISSUED",
        "dueAt",to.plusDays(terms));
  }

  @GetMapping("/partners/{partnerId}/invoices")
  public List<Map<String,Object>> invoices(@PathVariable UUID partnerId){
    return db.queryForList(
        "select id,period_start,period_end,total_minor,currency,status,due_at,created_at " +
        "from partner_invoices where partner_id=? order by created_at desc",
        partnerId);
  }
}
