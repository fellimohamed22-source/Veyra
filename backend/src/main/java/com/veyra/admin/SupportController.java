package com.veyra.admin;

import com.veyra.shared.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.util.*;

@RestController
@RequestMapping("/api/v1/support")
@PreAuthorize("hasAnyRole('SUPPORT','ADMIN')")
public class SupportController {
  private final JdbcTemplate db;

  public SupportController(JdbcTemplate db){ this.db=db; }

  @GetMapping("/bookings/{id}/timeline")
  public Map<String,Object> timeline(@PathVariable UUID id){
    List<Map<String,Object>> bookings=db.queryForList(
        "select id,creator_type,scheduled_at,status,payment_method,selected_driver_id,pickup_address,dropoff_address " +
        "from scheduled_bookings where id=?",
        id);
    if(bookings.isEmpty()){
      throw new ApiException(HttpStatus.NOT_FOUND,"BOOKING_NOT_FOUND");
    }

    Map<String,Object> result=new LinkedHashMap<>();
    result.put("booking",bookings.getFirst());
    result.put("history",db.queryForList(
        "select from_status,to_status,actor_type,actor_id,reason_code,created_at " +
        "from booking_status_history where booking_id=? order by created_at",
        id));
    result.put("messages",db.queryForList(
        "select cm.sender_user_id,cm.body,cm.sent_at from chat_messages cm " +
        "join chat_conversations cc on cc.id=cm.conversation_id " +
        "where cc.booking_id=? order by cm.sent_at",
        id));
    result.put("payments",db.queryForList(
        "select method,status,amount_minor,currency,created_at from payments where booking_id=? order by created_at",
        id));
    return result;
  }
}
