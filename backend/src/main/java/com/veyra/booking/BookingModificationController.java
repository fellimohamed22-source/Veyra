package com.veyra.booking;

import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import com.veyra.shared.DbTime;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.time.*;
import java.util.*;

@RestController
@RequestMapping("/api/v1/scheduled-bookings")
public class BookingModificationController {
  private final JdbcTemplate db;
  private final long minLeadMinutes;
  private final long maxOfferWindowHours;
  private final long normalCloseBeforeMinutes;
  private final long shortCloseBeforeMinutes;

  public BookingModificationController(
      JdbcTemplate db,
      @Value("${veyra.marketplace.min-lead-minutes}") long minLeadMinutes,
      @Value("${veyra.marketplace.max-offer-window-hours}") long maxOfferWindowHours,
      @Value("${veyra.marketplace.normal-close-before-minutes}") long normalCloseBeforeMinutes,
      @Value("${veyra.marketplace.short-close-before-minutes}") long shortCloseBeforeMinutes){
    this.db=db;
    this.minLeadMinutes=minLeadMinutes;
    this.maxOfferWindowHours=maxOfferWindowHours;
    this.normalCloseBeforeMinutes=normalCloseBeforeMinutes;
    this.shortCloseBeforeMinutes=shortCloseBeforeMinutes;
  }

  public record Point(
      @DecimalMin("-90") @DecimalMax("90") double lat,
      @DecimalMin("-180") @DecimalMax("180") double lng,
      @NotBlank String address){}

  public record UpdateRequest(
      @Valid Point pickup,
      @Valid Point dropoff,
      OffsetDateTime scheduledAt,
      UUID categoryId,
      @Min(1) @Max(9) Integer passengerCount,
      @Min(0) @Max(12) Integer baggageCount,
      @Size(max=1000) String customerNotes){}

  @PatchMapping("/{bookingId}")
  @Transactional
  public Map<String,Object> update(
      @PathVariable UUID bookingId,
      @Valid @RequestBody UpdateRequest request){

    List<Map<String,Object>> rows=db.queryForList(
        "select creator_user_id,partner_id,status,scheduled_at from scheduled_bookings where id=? for update",
        bookingId);
    if(rows.isEmpty()) throw new ApiException(HttpStatus.NOT_FOUND,"BOOKING_NOT_FOUND");

    Map<String,Object> booking=rows.getFirst();
    assertOwner(booking);

    String status=(String)booking.get("status");
    if(!Set.of("OPEN_FOR_OFFERS","OFFERS_RECEIVED").contains(status)){
      throw new ApiException(HttpStatus.CONFLICT,"BOOKING_MODIFICATION_REQUIRES_CANCEL_RECREATE");
    }

    boolean structural=request.pickup()!=null ||
        request.dropoff()!=null ||
        request.scheduledAt()!=null ||
        request.categoryId()!=null ||
        request.passengerCount()!=null ||
        request.baggageCount()!=null;

    OffsetDateTime targetScheduled=request.scheduledAt()!=null
        ?request.scheduledAt()
        :DbTime.toOffsetDateTime(booking.get("scheduled_at"));

    if(structural){
      long minutes=Duration.between(OffsetDateTime.now(),targetScheduled).toMinutes();
      if(minutes<minLeadMinutes){
        throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"LEAD_TIME_TOO_SHORT");
      }

      if(request.pickup()!=null){
        validateServiceZone(request.pickup());
      }

      if(request.pickup()!=null){
        db.update(
            "update scheduled_bookings set pickup=ST_SetSRID(ST_MakePoint(?,?),4326)::geography,pickup_address=? where id=?",
            request.pickup().lng(),request.pickup().lat(),request.pickup().address(),bookingId);
      }
      if(request.dropoff()!=null){
        db.update(
            "update scheduled_bookings set dropoff=ST_SetSRID(ST_MakePoint(?,?),4326)::geography,dropoff_address=? where id=?",
            request.dropoff().lng(),request.dropoff().lat(),request.dropoff().address(),bookingId);
      }
      if(request.scheduledAt()!=null){
        db.update("update scheduled_bookings set scheduled_at=? where id=?",request.scheduledAt(),bookingId);
      }
      if(request.categoryId()!=null){
        db.update("update scheduled_bookings set category_id=? where id=?",request.categoryId(),bookingId);
      }
      if(request.passengerCount()!=null){
        db.update("update scheduled_bookings set passenger_count=? where id=?",request.passengerCount(),bookingId);
      }
      if(request.baggageCount()!=null){
        db.update("update scheduled_bookings set baggage_count=? where id=?",request.baggageCount(),bookingId);
      }

      db.update(
          "update driver_offers set status='EXPIRED' where booking_id=? and status='ACTIVE'",
          bookingId);

      OffsetDateTime now=OffsetDateTime.now();
      long remainingMinutes=Duration.between(now,targetScheduled).toMinutes();
      OffsetDateTime close=remainingMinutes>=240
          ?earlier(targetScheduled.minusMinutes(normalCloseBeforeMinutes),now.plusHours(maxOfferWindowHours))
          :targetScheduled.minusMinutes(shortCloseBeforeMinutes);

      db.update(
          "update scheduled_bookings set status='OPEN_FOR_OFFERS',offer_window_ends_at=?,updated_at=now() where id=?",
          close,bookingId);

      db.update(
          "insert into outbox_events(aggregate_type,aggregate_id,event_type,payload) " +
          "values ('BOOKING',?,'booking.published',jsonb_build_object('bookingId',?::text,'republished',true))",
          bookingId,bookingId);
    }

    if(request.customerNotes()!=null){
      db.update(
          "update scheduled_bookings set customer_notes=?,updated_at=now() where id=?",
          request.customerNotes(),bookingId);
    }

    return db.queryForMap(
        "select id,pickup_address,dropoff_address,scheduled_at,category_id,passenger_count,baggage_count,customer_notes,status,offer_window_ends_at " +
        "from scheduled_bookings where id=?",
        bookingId);
  }

  private void assertOwner(Map<String,Object> booking){
    UUID userId=CurrentUser.id();
    if(userId.equals(booking.get("creator_user_id"))) return;
    UUID partnerId=(UUID)booking.get("partner_id");
    if(partnerId!=null){
      Integer count=db.queryForObject(
          "select count(*) from partner_users where partner_id=? and user_id=? and status='ACTIVE'",
          Integer.class,partnerId,userId);
      if(count!=null&&count>0) return;
    }
    throw new ApiException(HttpStatus.FORBIDDEN,"FORBIDDEN");
  }

  private void validateServiceZone(Point pickup){
    Integer active=db.queryForObject(
        "select count(*) from service_zone_versions where status='ACTIVE' " +
        "and effective_from<=now() and (effective_to is null or effective_to>now())",
        Integer.class);
    if(active==null||active==0) return;

    Integer covered=db.queryForObject(
        "select count(*) from service_zone_versions where status='ACTIVE' " +
        "and effective_from<=now() and (effective_to is null or effective_to>now()) " +
        "and ST_Covers(polygon::geometry,ST_SetSRID(ST_MakePoint(?,?),4326))",
        Integer.class,pickup.lng(),pickup.lat());
    if(covered==null||covered==0){
      throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"PICKUP_OUTSIDE_SERVICE_ZONE");
    }
  }

  private OffsetDateTime earlier(OffsetDateTime a,OffsetDateTime b){
    return a.isBefore(b)?a:b;
  }
}
