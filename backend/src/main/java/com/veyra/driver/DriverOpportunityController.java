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
        "sb.category_id,vc.display_name as category_name,sb.passenger_count,sb.baggage_count,sb.customer_notes,sb.offer_visibility_mode," +
        "ST_Y(sb.pickup::geometry) as pickup_lat,ST_X(sb.pickup::geometry) as pickup_lng,ST_Y(sb.dropoff::geometry) as dropoff_lat,ST_X(sb.dropoff::geometry) as dropoff_lng," +
        com.veyra.booking.BookingController.CUSTOMER_FAVORITE_SQL+" as customer_favorite," +
        com.veyra.booking.BookingController.CUSTOMER_DISPLAY_NAME_SQL+" as customer_display_name," +
        com.veyra.booking.BookingController.CUSTOMER_RATING_SQL+" as customer_rating," +
        com.veyra.booking.BookingController.CUSTOMER_RATING_COUNT_SQL+" as customer_rating_count," +
        com.veyra.booking.BookingController.ELIGIBLE_VEHICLE_SQL+" as has_eligible_vehicle " +
        "from scheduled_bookings sb join vehicle_categories vc on vc.id=sb.category_id " +
        "where sb.id=? and sb.status in ('OPEN_FOR_OFFERS','OFFERS_RECEIVED') and sb.offer_window_ends_at>now()",
        driverId,driverId,bookingId);
    if(rows.isEmpty()){
      throw new ApiException(HttpStatus.GONE,"BOOKING_OFFERS_CLOSED");
    }

    Map<String,Object> result=new LinkedHashMap<>(rows.getFirst());
    List<Map<String,Object>> ownOffers=db.queryForList(
        "select proposed_amount_minor from driver_offers where booking_id=? and driver_id=? and status='ACTIVE'",
        bookingId,driverId);
    result.put("hasActiveOffer",!ownOffers.isEmpty());
    if(!ownOffers.isEmpty())result.put("ownActiveOfferAmountMinor",ownOffers.getFirst().get("proposed_amount_minor"));
    if("BEST_VISIBLE".equals(result.get("offer_visibility_mode"))){
      // Same rule as at submission time: lowest price among the OTHER
      // drivers' active offers only, never an identity, never blocking.
      Long bestOthers=db.queryForObject(
          "select min(proposed_amount_minor) from driver_offers where booking_id=? and status='ACTIVE' and expires_at>now() and driver_id<>?",
          Long.class,bookingId,driverId);
      result.put("currentBestOtherOfferMinor",bestOthers);
    }
    return result;
  }

  /**
   * DR-04 price preview (DEC-01 method A): the driver types their net
   * price and sees the customer total, using exactly the resolution and
   * arithmetic applied when the offer is submitted. Read-only.
   */
  @GetMapping("/{bookingId}/quote")
  public Map<String,Object> quote(@PathVariable UUID bookingId,@RequestParam long amountMinor){
    UUID driverId=driverId();
    assertEligible(driverId);
    if(amountMinor<=0||amountMinor>10_000_000)throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"INVALID_AMOUNT");
    Integer open=db.queryForObject(
        "select count(*) from scheduled_bookings where id=? and status in ('OPEN_FOR_OFFERS','OFFERS_RECEIVED') and offer_window_ends_at>now()",
        Integer.class,bookingId);
    if(open==null||open==0)throw new ApiException(HttpStatus.GONE,"BOOKING_OFFERS_CLOSED");
    var q=new com.veyra.commission.CommissionEngine(db).quoteForBooking(bookingId,amountMinor);
    Map<String,Object> result=new LinkedHashMap<>();
    result.put("driverNetMinor",amountMinor);
    q.putInto(result);
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
