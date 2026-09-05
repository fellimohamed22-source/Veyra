package com.veyra.partner;

import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

import java.util.*;

@RestController
@RequestMapping("/api/v1/partner/{partnerId}/bookings")
public class PartnerBookingController {
  private final JdbcTemplate db;

  public PartnerBookingController(JdbcTemplate db){
    this.db=db;
  }

  @GetMapping
  public List<Map<String,Object>> list(@PathVariable UUID partnerId){
    assertMember(partnerId);
    return db.queryForList(
        "select id,pickup_address,dropoff_address,scheduled_at,status,payment_method,selected_driver_id,beneficiary_name_snapshot " +
        "from scheduled_bookings where partner_id=? order by scheduled_at desc limit 500",
        partnerId);
  }

  private void assertMember(UUID partnerId){
    Integer count=db.queryForObject(
        "select count(*) from partner_users where partner_id=? and user_id=? and status='ACTIVE'",
        Integer.class,partnerId,CurrentUser.id());
    if(count==null || count==0){
      throw new ApiException(HttpStatus.FORBIDDEN,"PARTNER_SCOPE_FORBIDDEN");
    }
  }
}
