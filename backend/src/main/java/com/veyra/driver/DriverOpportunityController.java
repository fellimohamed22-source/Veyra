package com.veyra.driver;

import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

import java.util.*;

@RestController
@RequestMapping("/api/v1/driver/opportunities")
public class DriverOpportunityController {
  private final JdbcTemplate db;

  public DriverOpportunityController(JdbcTemplate db){
    this.db=db;
  }

  @GetMapping("/{bookingId}")
  public Map<String,Object> detail(@PathVariable UUID bookingId){
    UUID driverId=driverId();
    assertEligible(driverId);

    List<Map<String,Object>> rows=db.queryForList(
        "select sb.id,sb.pickup_address,sb.dropoff_address,sb.scheduled_at,sb.status,sb.offer_window_ends_at," +
        "sb.category_id,vc.display_name as category_name,sb.passenger_count,sb.baggage_count,sb.customer_notes " +
        "from scheduled_bookings sb join vehicle_categories vc on vc.id=sb.category_id " +
        "where sb.id=? and sb.status in ('OPEN_FOR_OFFERS','OFFERS_RECEIVED') and sb.offer_window_ends_at>now()",
        bookingId);
    if(rows.isEmpty()){
      throw new ApiException(HttpStatus.GONE,"BOOKING_OFFERS_CLOSED");
    }

    Map<String,Object> result=new LinkedHashMap<>(rows.getFirst());
    Integer ownOffer=db.queryForObject(
        "select count(*) from driver_offers where booking_id=? and driver_id=? and status='ACTIVE'",
        Integer.class,bookingId,driverId);
    result.put("hasActiveOffer",ownOffer!=null&&ownOffer>0);
    return result;
  }

  private UUID driverId(){
    List<UUID> rows=db.queryForList(
        "select id from drivers where user_id=?",
        UUID.class,CurrentUser.id());
    if(rows.isEmpty()) throw new ApiException(HttpStatus.FORBIDDEN,"DRIVER_PROFILE_REQUIRED");
    return rows.getFirst();
  }

  private void assertEligible(UUID driverId){
    Integer n=db.queryForObject(
        "select count(*) from drivers where id=? and status='ACTIVE' and kyc_status='APPROVED' and marketplace_enabled=true",
        Integer.class,driverId);
    if(n==null||n==0) throw new ApiException(HttpStatus.FORBIDDEN,"DRIVER_NOT_ELIGIBLE");
  }
}
