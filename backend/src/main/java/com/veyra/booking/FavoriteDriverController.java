package com.veyra.booking;

import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.util.*;

@RestController
@RequestMapping("/api/v1")
public class FavoriteDriverController {
  private final JdbcTemplate db;
  public FavoriteDriverController(JdbcTemplate db){this.db=db;}

  @PostMapping("/scheduled-bookings/{bookingId}/favorite-driver")
  @Transactional
  public Map<String,Object> favorite(@PathVariable UUID bookingId){
    UUID userId=CurrentUser.id();
    List<UUID> drivers=db.queryForList(
      "select selected_driver_id from scheduled_bookings where id=? and creator_user_id=? and status in ('COMPLETED','CLOSED') and selected_driver_id is not null",
      UUID.class,bookingId,userId);
    if(drivers.isEmpty())throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"COMPLETED_RIDE_REQUIRED");
    UUID driverId=drivers.getFirst();
    db.update("insert into client_favorite_drivers(client_user_id,driver_id) values (?,?) on conflict do nothing",userId,driverId);
    return Map.of("driverId",driverId,"favorite",true);
  }

  @DeleteMapping("/favorite-drivers/{driverId}")
  @Transactional
  public Map<String,Object> unfavorite(@PathVariable UUID driverId){
    db.update("delete from client_favorite_drivers where client_user_id=? and driver_id=?",CurrentUser.id(),driverId);
    return Map.of("driverId",driverId,"favorite",false);
  }

  @GetMapping("/favorite-drivers")
  public List<Map<String,Object>> favorites(){
    return db.queryForList(
      "select d.id as driver_id,u.first_name,u.last_name,d.rating,v.brand as vehicle_brand,v.model as vehicle_model,v.color as vehicle_color,v.year as vehicle_year " +
      "from client_favorite_drivers f join drivers d on d.id=f.driver_id join users u on u.id=d.user_id " +
      "left join vehicles v on v.driver_id=d.id and v.status='APPROVED' where f.client_user_id=? order by f.created_at desc",
      CurrentUser.id());
  }

  @PostMapping("/scheduled-bookings/{bookingId}/repeat-driver")
  public Map<String,Object> repeatDriver(@PathVariable UUID bookingId){
    UUID userId=CurrentUser.id();
    List<Map<String,Object>> rows=db.queryForList(
      "select sb.selected_driver_id,sb.pickup_address,sb.dropoff_address,ST_Y(sb.pickup::geometry) pickup_lat,ST_X(sb.pickup::geometry) pickup_lng,"+
      "ST_Y(sb.dropoff::geometry) dropoff_lat,ST_X(sb.dropoff::geometry) dropoff_lng,sb.category_id,sb.passenger_count,sb.baggage_count,sb.payment_method "+
      "from scheduled_bookings sb where sb.id=? and sb.creator_user_id=? and sb.status in ('COMPLETED','CLOSED') and sb.selected_driver_id is not null",
      bookingId,userId);
    if(rows.isEmpty())throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"COMPLETED_RIDE_REQUIRED");
    Map<String,Object> r=new LinkedHashMap<>(rows.getFirst());
    UUID driverId=(UUID)r.get("selected_driver_id");
    db.update("insert into client_favorite_drivers(client_user_id,driver_id) values (?,?) on conflict do nothing",userId,driverId);
    r.put("preferredDriverId",driverId);
    r.put("requestMode","PREFERRED_DRIVER_FIRST");
    r.put("fallback","MARKETPLACE");
    return r;
  }
}
