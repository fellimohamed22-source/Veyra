package com.veyra.location;

import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

import java.util.*;

@RestController
@RequestMapping("/api/v1/bookings/{bookingId}/location")
public class BookingLocationController {
  private final JdbcTemplate db;

  public BookingLocationController(JdbcTemplate db){
    this.db=db;
  }

  @GetMapping
  public Map<String,Object> current(@PathVariable UUID bookingId){
    authorize(bookingId);
    List<Map<String,Object>> rows=db.queryForList(
      "select cdl.lat,cdl.lng,cdl.accuracy_m,cdl.heading,cdl.speed_mps,cdl.sequence_no,cdl.recorded_at,cdl.updated_at " +
      "from current_driver_locations cdl join scheduled_bookings sb on sb.id=cdl.booking_id " +
      "where cdl.booking_id=? and sb.status in ('DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_PROGRESS') " +
      "and (sb.scheduled_at at time zone 'Europe/Paris')::date=(now() at time zone 'Europe/Paris')::date",
      bookingId);
    if(rows.isEmpty()){
      return Map.of("available",false);
    }
    Map<String,Object> result=new LinkedHashMap<>(rows.getFirst());
    result.put("available",true);
    return result;
  }

  private void authorize(UUID bookingId){
    UUID userId=CurrentUser.id();
    Integer allowed=db.queryForObject(
      "select count(*) from scheduled_bookings sb " +
      "left join drivers d on d.id=sb.selected_driver_id " +
      "left join partner_users pu on pu.partner_id=sb.partner_id and pu.user_id=? and pu.status='ACTIVE' " +
      "where sb.id=? and (sb.creator_user_id=? or d.user_id=? or pu.id is not null)",
      Integer.class,userId,bookingId,userId,userId);
    if(allowed==null||allowed==0){
      throw new ApiException(HttpStatus.FORBIDDEN,"LOCATION_FORBIDDEN");
    }
  }
}
