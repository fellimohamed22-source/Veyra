package com.veyra.finance;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;
import java.util.*;
@RestController
@RequestMapping("/api/v1/finance")
@PreAuthorize("hasAnyRole('FINANCE','ADMIN')")
public class FinanceOpsController {
  private final JdbcTemplate db;
  public FinanceOpsController(JdbcTemplate db){this.db=db;}

  @GetMapping("/cash-debts")
  public List<Map<String,Object>> debts(){
    return db.queryForList("select dpd.id,dpd.driver_id,dpd.booking_id,dpd.amount_minor,dpd.paid_amount_minor,dpd.currency,dpd.status from driver_platform_debts dpd order by dpd.id desc");
  }

  @PostMapping("/cash-debts/{id}/settle")
  public void settle(@PathVariable UUID id,@RequestParam long amountMinor){
    var x=db.queryForMap("select amount_minor,paid_amount_minor from driver_platform_debts where id=? for update",id);
    long total=((Number)x.get("amount_minor")).longValue(),paid=((Number)x.get("paid_amount_minor")).longValue();
    long next=Math.min(total,paid+amountMinor);
    db.update("update driver_platform_debts set paid_amount_minor=?,status=case when ?>=amount_minor then 'PAID' else 'PARTIALLY_PAID' end where id=?",next,next,id);
  }

  @GetMapping("/payables")
  public List<Map<String,Object>> payables(){
    return db.queryForList("select id,driver_id,booking_id,amount_minor,currency,status from driver_payables order by id desc");
  }
}
