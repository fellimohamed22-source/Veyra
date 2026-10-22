package com.veyra.finance;

import com.veyra.security.CurrentUser;
import com.veyra.security.PinCrypto;
import com.veyra.shared.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.util.*;

/**
 * Bank details for driver payouts (finance team only). Reading the full IBAN
 * is audited; elsewhere only the last four digits are shown.
 */
@RestController
@RequestMapping("/api/v1/finance/drivers")
@PreAuthorize("hasAnyRole('FINANCE','ADMIN')")
public class DriverBankController {
  private final JdbcTemplate db;
  private final PinCrypto crypto;

  public DriverBankController(JdbcTemplate db, PinCrypto crypto) {
    this.db = db;
    this.crypto = crypto;
  }

  @GetMapping("/{driverId}/bank")
  public Map<String, Object> bank(@PathVariable UUID driverId) {
    List<Map<String, Object>> rows = db.queryForList(
        "select b.holder_name,b.iban_encrypted,b.bic,b.updated_at,trim(coalesce(u.first_name,'')||' '||coalesce(u.last_name,'')) as driver_name " +
        "from driver_bank_accounts b join drivers d on d.id=b.driver_id join users u on u.id=d.user_id where b.driver_id=?", driverId);
    if (rows.isEmpty()) throw new ApiException(HttpStatus.NOT_FOUND, "BANK_ACCOUNT_NOT_FOUND");
    Map<String, Object> r = rows.getFirst();
    db.update("insert into audit_logs(actor_id,actor_type,action,entity_type,entity_id) values (?,'ADMIN','DRIVER_BANK_VIEWED','DRIVER',?)",
        CurrentUser.id(), driverId);
    Map<String, Object> out = new LinkedHashMap<>();
    out.put("driverName", r.get("driver_name"));
    out.put("holderName", r.get("holder_name"));
    out.put("iban", crypto.decrypt((String) r.get("iban_encrypted")));
    out.put("bic", r.get("bic"));
    out.put("updatedAt", r.get("updated_at"));
    return out;
  }
}
