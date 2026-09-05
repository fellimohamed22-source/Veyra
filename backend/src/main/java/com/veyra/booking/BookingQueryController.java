package com.veyra.booking;

import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

import java.util.*;

@RestController
@RequestMapping("/api/v1/scheduled-bookings")
public class BookingQueryController {
  private final JdbcTemplate db;

  public BookingQueryController(JdbcTemplate db){
    this.db=db;
  }

  @GetMapping("/{bookingId}")
  public Map<String,Object> detail(@PathVariable UUID bookingId){
    UUID userId=CurrentUser.id();
    List<Map<String,Object>> rows=db.queryForList(
        "select sb.id,sb.creator_type,sb.creator_user_id,sb.partner_id,sb.beneficiary_name_snapshot," +
        "sb.beneficiary_phone_snapshot,sb.pickup_address,sb.dropoff_address,sb.scheduled_at,sb.status," +
        "sb.payment_method,sb.offer_window_ends_at,sb.selected_driver_id," +
        "bfs.driver_net_amount_minor,bfs.platform_commission_amount_minor,bfs.customer_total_amount_minor,bfs.currency," +
        "du.first_name as driver_first_name,du.last_name as driver_last_name,du.phone as driver_phone,d.rating as driver_rating," +
        "v.brand as vehicle_brand,v.model as vehicle_model,v.plate_number,v.color as vehicle_color " +
        "from scheduled_bookings sb " +
        "left join booking_financial_snapshots bfs on bfs.booking_id=sb.id " +
        "left join drivers d on d.id=sb.selected_driver_id " +
        "left join users du on du.id=d.user_id " +
        "left join vehicles v on v.driver_id=d.id and v.status='APPROVED' " +
        "where sb.id=? limit 1",
        bookingId);

    if(rows.isEmpty()){
      throw new ApiException(HttpStatus.NOT_FOUND,"BOOKING_NOT_FOUND");
    }

    Map<String,Object> row=rows.getFirst();
    boolean allowed=userId.equals(row.get("creator_user_id"));

    UUID partnerId=(UUID)row.get("partner_id");
    if(!allowed && partnerId!=null){
      Integer member=db.queryForObject(
          "select count(*) from partner_users where partner_id=? and user_id=? and status='ACTIVE'",
          Integer.class,partnerId,userId);
      allowed=member!=null && member>0;
    }

    UUID selectedDriverId=(UUID)row.get("selected_driver_id");
    if(!allowed && selectedDriverId!=null){
      Integer driver=db.queryForObject(
          "select count(*) from drivers where id=? and user_id=?",
          Integer.class,selectedDriverId,userId);
      allowed=driver!=null && driver>0;
    }

    if(!allowed){
      throw new ApiException(HttpStatus.FORBIDDEN,"FORBIDDEN");
    }

    return new LinkedHashMap<>(row);
  }
}
