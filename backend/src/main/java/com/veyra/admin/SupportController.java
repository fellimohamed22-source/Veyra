package com.veyra.admin;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;
import java.util.*;
@RestController
@RequestMapping("/api/v1/support")
@PreAuthorize("hasAnyRole('SUPPORT','ADMIN')")
public class SupportController {
  private final JdbcTemplate db;
  public SupportController(JdbcTemplate db){this.db=db;}

  @GetMapping("/bookings/{id}/timeline")
  public Map<String,Object> timeline(@PathVariable UUID id){
    return Map.of(
      "booking",db.queryForMap("select id,creator_type,scheduled_at,status,payment_method,selected_driver_id,pickup_address,dropoff_address from scheduled_bookings where id=?",id),
      "history",db.queryForList("select from_status,to_status,actor_type,actor_id,reason_code,created_at from booking_status_history where booking_id=? order by created_at",id),
      "messages",db.queryForList("select cm.sender_user_id,cm.body,cm.sent_at from chat_messages cm join chat_conversations cc on cc.id=cm.conversation_id where cc.booking_id=? order by cm.sent_at",id),
      "payments",db.queryForList("select method,status,amount_minor,currency,created_at from payments where booking_id=?",id)
    );
  }
}
