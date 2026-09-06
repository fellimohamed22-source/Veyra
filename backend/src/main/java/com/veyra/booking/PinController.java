package com.veyra.booking;
import com.veyra.security.*;
import com.veyra.shared.ApiException;
import com.veyra.shared.DbTime;
import org.springframework.http.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;
import java.time.*;
import java.util.*;
@RestController @RequestMapping("/api/v1/bookings")public class PinController{
    private final JdbcTemplate db;
    private final PinCrypto crypto;
    public PinController(JdbcTemplate d,PinCrypto c){
        db=d;
        crypto=c;
    }
    @GetMapping("/{id}/pin")Map<String,Object>pin(@PathVariable UUID id){
        List<Map<String,Object>>x=db.queryForList("select creator_user_id,partner_id,scheduled_at,status,pin_encrypted from scheduled_bookings where id=?",id);
        if(x.isEmpty())throw new ApiException(HttpStatus.NOT_FOUND,"BOOKING_NOT_FOUND");
        Map<String,Object>b=x.getFirst();
        UUID u=CurrentUser.id();
        boolean owner=u.equals(b.get("creator_user_id"));
        if(!owner&&b.get("partner_id")!=null)owner=db.queryForObject("select count(*) from partner_users where partner_id=? and user_id=?",Integer.class,b.get("partner_id"),u)>0;
        if(!owner)throw new ApiException(HttpStatus.FORBIDDEN,"FORBIDDEN");
        OffsetDateTime at=DbTime.toOffsetDateTime(b.get("scheduled_at"));
        if(OffsetDateTime.now().isBefore(at.minusHours(1)))throw new ApiException(HttpStatus.TOO_EARLY,"PIN_NOT_YET_AVAILABLE");
        if(b.get("pin_encrypted")==null)throw new ApiException(HttpStatus.CONFLICT,"PIN_NOT_CREATED");
        return Map.of("pin",crypto.decrypt((String)b.get("pin_encrypted")),"validForBookingId",id);
    }
}
