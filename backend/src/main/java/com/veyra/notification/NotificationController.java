package com.veyra.notification;

import com.veyra.security.CurrentUser;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

import java.util.*;

@RestController
@RequestMapping("/api/v1/notifications")
public class NotificationController {
  private final JdbcTemplate db;

  public NotificationController(JdbcTemplate db){
    this.db=db;
  }

  @GetMapping
  public List<Map<String,Object>> mine(){
    return db.queryForList(
      "select n.id,n.event_type,n.channel,n.template_code,n.status,n.data,n.sent_at,n.created_at," +
      "sb.id as booking_id,sb.pickup_address,sb.dropoff_address,sb.scheduled_at,sb.status as booking_status," +
      "o.id as offer_id,o.proposed_amount_minor as offer_amount_minor,o.currency as offer_currency," +
      "u.first_name as driver_first_name,u.last_name as driver_last_name " +
      "from notifications n " +
      "left join scheduled_bookings sb on sb.id=(nullif(n.data->>'bookingId',''))::uuid " +
      "left join driver_offers o on o.id=(nullif(n.data->>'offerId',''))::uuid " +
      "left join drivers d on d.id=o.driver_id " +
      "left join users u on u.id=d.user_id " +
      "where n.user_id=? order by n.created_at desc limit 100",
      CurrentUser.id());
  }
}
