package com.veyra.location;
import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import com.veyra.shared.DbTime;
import org.springframework.http.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.web.bind.annotation.*;
import java.time.*;
import java.util.*;
@RestController @RequestMapping("/api/v1/driver/location")public class LocationController{
    private final JdbcTemplate db;
    private final SimpMessagingTemplate ws;
    public LocationController(JdbcTemplate d,SimpMessagingTemplate w){
        db=d;
        ws=w;
    }
    public record Pos(UUID bookingId,double lat,double lng,Double accuracyM,Double heading,Double speedMps,long sequenceNo,OffsetDateTime recordedAt){
    }
    @PostMapping void update(@RequestBody Pos p){
        List<UUID> drivers=db.queryForList("select id from drivers where user_id=?",UUID.class,CurrentUser.id());
        if(drivers.isEmpty())throw new ApiException(HttpStatus.FORBIDDEN,"DRIVER_PROFILE_REQUIRED");
        UUID d=drivers.getFirst();
        Integer ok=db.queryForObject("select count(*) from scheduled_bookings where id=? and selected_driver_id=? and status in ('DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_PROGRESS')",Integer.class,p.bookingId(),d);
        if(ok==0)throw new ApiException(HttpStatus.FORBIDDEN,"LOCATION_NOT_ALLOWED");
        List<Map<String,Object>> previous=db.queryForList(
            "select booking_id,sequence_no,recorded_at from current_driver_locations where driver_id=?",
            d);
        if(!previous.isEmpty()){
            Map<String,Object> old=previous.getFirst();
            UUID oldBooking=(UUID)old.get("booking_id");
            long oldSequence=((Number)old.get("sequence_no")).longValue();
            OffsetDateTime oldRecorded=DbTime.toOffsetDateTime(old.get("recorded_at"));
            // sequence_no belongs to one app tracking stream. Reinstalling or
            // restarting the app must not permanently brick live tracking:
            // a genuinely newer GPS fix for the same booking is accepted even
            // if its new stream restarted with a lower sequence number.
            if(p.bookingId().equals(oldBooking) &&
               p.sequenceNo()<=oldSequence &&
               p.recordedAt()!=null &&
               oldRecorded!=null &&
               !p.recordedAt().isAfter(oldRecorded)){
                throw new ApiException(HttpStatus.CONFLICT,"LOCATION_REPLAY");
            }
        }
        db.update("insert into current_driver_locations(driver_id,booking_id,lat,lng,accuracy_m,heading,speed_mps,sequence_no,recorded_at) values (?,?,?,?,?,?,?,?,?) on conflict(driver_id) do update set booking_id=excluded.booking_id,lat=excluded.lat,lng=excluded.lng,accuracy_m=excluded.accuracy_m,heading=excluded.heading,speed_mps=excluded.speed_mps,sequence_no=excluded.sequence_no,recorded_at=excluded.recorded_at,updated_at=now()",d,p.bookingId(),p.lat(),p.lng(),p.accuracyM(),p.heading(),p.speedMps(),p.sequenceNo(),p.recordedAt());
        ws.convertAndSend("/topic/bookings/"+p.bookingId()+"/location",p);
    }
}
