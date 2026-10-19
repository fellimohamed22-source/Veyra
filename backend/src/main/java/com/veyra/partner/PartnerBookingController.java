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
        "select sb.id,sb.pickup_address,sb.dropoff_address,sb.scheduled_at,sb.status,sb.payment_method,sb.payer_type,sb.selected_driver_id,sb.beneficiary_name_snapshot,sb.partner_reference," +
        "sb.passenger_count,sb.baggage_count,sb.customer_notes,sb.offer_window_ends_at,vc.display_name as category_name," +
        "bfs.customer_total_amount_minor,bfs.currency," +
        com.veyra.booking.AvailableOfferQuery.COUNT_SQL+" as offer_count,"+com.veyra.booking.AvailableOfferQuery.BEST_TOTAL_SQL+" as best_offer_total_minor " +
        "from scheduled_bookings sb join vehicle_categories vc on vc.id=sb.category_id " +
        "left join booking_financial_snapshots bfs on bfs.booking_id=sb.id " +
        "where sb.partner_id=? order by sb.scheduled_at desc limit 500",
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
