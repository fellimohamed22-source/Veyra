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
        "sb.beneficiary_phone_snapshot,sb.pickup_address,sb.dropoff_address,ST_Y(sb.pickup::geometry) as pickup_lat,ST_X(sb.pickup::geometry) as pickup_lng,ST_Y(sb.dropoff::geometry) as dropoff_lat,ST_X(sb.dropoff::geometry) as dropoff_lng," +
        "round(ST_Distance(sb.pickup,sb.dropoff))::bigint as trip_distance_meters,sb.scheduled_at,sb.passenger_count,sb.baggage_count,sb.customer_notes,sb.status," +
        "sb.payment_method,sb.offer_window_ends_at,sb.selected_driver_id," +
        "bfs.driver_net_amount_minor,bfs.platform_commission_amount_minor,bfs.customer_total_amount_minor,bfs.currency," +
        "du.first_name as driver_first_name,du.last_name as driver_last_name,du.phone as driver_phone,d.rating as driver_rating,d.kyc_status as driver_kyc_status,d.status as driver_status," +
        "v.brand as vehicle_brand,v.model as vehicle_model,v.plate_number,v.color as vehicle_color,v.year as vehicle_year,v.status as vehicle_status," +
        "cdl.lat as driver_lat,cdl.lng as driver_lng,cdl.heading as driver_heading,cdl.speed_mps as driver_speed_mps,cdl.recorded_at as driver_location_recorded_at " +
        "from scheduled_bookings sb " +
        "left join booking_financial_snapshots bfs on bfs.booking_id=sb.id " +
        "left join drivers d on d.id=sb.selected_driver_id " +
        "left join users du on du.id=d.user_id " +
        "left join lateral (select v0.* from vehicles v0 where v0.driver_id=d.id and v0.status='APPROVED' and v0.category_id=sb.category_id order by v0.id limit 1) v on true " +
        "left join current_driver_locations cdl on cdl.driver_id=sb.selected_driver_id and cdl.booking_id=sb.id " +
        "where sb.id=? limit 1",
        bookingId);

    if(rows.isEmpty()) throw new ApiException(HttpStatus.NOT_FOUND,"BOOKING_NOT_FOUND");

    Map<String,Object> row=rows.getFirst();
    assertAllowed(row,userId);
    Map<String,Object> result=new LinkedHashMap<>(row);

    String status=String.valueOf(row.get("status"));
    boolean driverSelected=row.get("selected_driver_id")!=null;
    result.put("driverSelected",driverSelected);
    result.put("driverCommitted",driverSelected && Set.of("CONFIRMED","DRIVER_EN_ROUTE","DRIVER_ARRIVED","IN_PROGRESS","COMPLETED","CLOSED").contains(status));
    result.put("driverVerified",driverSelected && "APPROVED".equals(row.get("driver_kyc_status")) && "ACTIVE".equals(row.get("driver_status")));
    result.put("vehicleVerified",driverSelected && "APPROVED".equals(row.get("vehicle_status")));
    result.put("liveTrackingEligible",Set.of("DRIVER_EN_ROUTE","DRIVER_ARRIVED","IN_PROGRESS").contains(status));
    result.put("liveTrackingFresh",row.get("driver_location_recorded_at")!=null);
    result.put("canContactDriver",driverSelected && Set.of("CONFIRMED","DRIVER_EN_ROUTE","DRIVER_ARRIVED","IN_PROGRESS").contains(status));
    result.put("rideStarted",Set.of("IN_PROGRESS","COMPLETED").contains(status));
    result.put("rideCompleted","COMPLETED".equals(status));

    return result;
  }

  @GetMapping("/{bookingId}/timeline")
  public List<Map<String,Object>> timeline(@PathVariable UUID bookingId){
    UUID userId=CurrentUser.id();
    List<Map<String,Object>> rows=db.queryForList(
        "select creator_user_id,partner_id,selected_driver_id from scheduled_bookings where id=?",
        bookingId);
    if(rows.isEmpty()) throw new ApiException(HttpStatus.NOT_FOUND,"BOOKING_NOT_FOUND");
    assertAllowed(rows.getFirst(),userId);
    return db.queryForList(
        "select from_status,to_status,actor_type,reason_code,created_at from booking_status_history where booking_id=? order by created_at",
        bookingId);
  }

  private void assertAllowed(Map<String,Object> row,UUID userId){
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

    if(!allowed) throw new ApiException(HttpStatus.FORBIDDEN,"FORBIDDEN");
  }
}
