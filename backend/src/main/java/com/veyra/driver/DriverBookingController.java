package com.veyra.driver;

import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

import java.util.*;

@RestController
@RequestMapping("/api/v1/driver/bookings")
public class DriverBookingController {
  private final JdbcTemplate db;

  public DriverBookingController(JdbcTemplate db) {
    this.db = db;
  }

  @GetMapping
  public List<Map<String, Object>> mine(@RequestParam(defaultValue="upcoming") String scope,
      @RequestParam(required=false) String status, @RequestParam(defaultValue="asc") String sort,
      @RequestParam(required=false) Integer page) {
    UUID driverId = driverId();
    String states = "('CONFIRMED','DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_PROGRESS')";
    if ("history".equals(scope)) {
      states = "('COMPLETED','CLOSED','CANCELLED','DRIVER_CANCELLED','CUSTOMER_NO_SHOW')";
    }
    if ("all".equals(scope)) states="('CONFIRMED','DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_PROGRESS','COMPLETED','CLOSED','CANCELLED','DRIVER_CANCELLED','CUSTOMER_NO_SHOW')";
    List<Object> args=new ArrayList<>(); args.add(driverId);
    String filter="";
    if(status!=null&&!status.isBlank()){filter=" and sb.status=?";args.add(status);}
    String paging=page==null?"":" limit 10 offset "+(Math.max(0,Math.min(page,100000))*10);
    return db.queryForList(
        "select sb.id,sb.pickup_address,sb.dropoff_address,ST_Y(sb.pickup::geometry) as pickup_lat,ST_X(sb.pickup::geometry) as pickup_lng,ST_Y(sb.dropoff::geometry) as dropoff_lat,ST_X(sb.dropoff::geometry) as dropoff_lng,sb.scheduled_at,sb.status," +
        "sb.payment_method,vc.display_name as category_name,sb.passenger_count,sb.baggage_count,bfs.driver_net_amount_minor,bfs.platform_commission_amount_minor,bfs.customer_total_amount_minor,bfs.currency " +
        "from scheduled_bookings sb join vehicle_categories vc on vc.id=sb.category_id left join booking_financial_snapshots bfs on bfs.booking_id=sb.id " +
        "where sb.selected_driver_id=? and sb.status in " + states + filter + " order by sb.scheduled_at "+("desc".equals(sort)?"desc":"asc")+",sb.id"+paging,
        args.toArray());
  }

  @GetMapping("/{bookingId}")
  public Map<String, Object> detail(@PathVariable UUID bookingId) {
    UUID driverId = driverId();
    List<Map<String, Object>> rows = db.queryForList(
        "select sb.id,sb.pickup_address,sb.dropoff_address,ST_Y(sb.pickup::geometry) as pickup_lat,ST_X(sb.pickup::geometry) as pickup_lng,ST_Y(sb.dropoff::geometry) as dropoff_lat,ST_X(sb.dropoff::geometry) as dropoff_lng,sb.scheduled_at,sb.status,sb.payment_method," +
        "coalesce(sb.beneficiary_name_snapshot,concat(cu.first_name,' ',coalesce(cu.last_name,''))) as customer_name," +
        "coalesce(sb.beneficiary_phone_snapshot,cu.phone) as customer_phone,sb.passenger_count,sb.baggage_count,sb.customer_notes,vc.display_name as category_name," +
        "(select max(created_at) from booking_status_history where booking_id=sb.id and to_status='DRIVER_ARRIVED') as arrived_at," +
        "(select p.status from payments p where p.booking_id=sb.id order by p.created_at desc limit 1) as payment_status," +
        "bfs.driver_net_amount_minor,bfs.platform_commission_amount_minor,bfs.customer_total_amount_minor,bfs.currency " +
        "from scheduled_bookings sb " +
        "join users cu on cu.id=sb.creator_user_id join vehicle_categories vc on vc.id=sb.category_id " +
        "left join booking_financial_snapshots bfs on bfs.booking_id=sb.id " +
        "where sb.id=? and sb.selected_driver_id=?",
        bookingId,
        driverId);
    if (rows.isEmpty()) {
      throw new ApiException(HttpStatus.NOT_FOUND, "BOOKING_NOT_FOUND");
    }
    return rows.getFirst();
  }

  private UUID driverId() {
    List<UUID> rows = db.queryForList(
        "select id from drivers where user_id=?",
        UUID.class,
        CurrentUser.id());
    if (rows.isEmpty()) {
      throw new ApiException(HttpStatus.FORBIDDEN, "DRIVER_PROFILE_REQUIRED");
    }
    return rows.getFirst();
  }
}
