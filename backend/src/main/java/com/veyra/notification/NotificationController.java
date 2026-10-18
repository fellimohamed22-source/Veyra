package com.veyra.notification;

import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

import java.util.*;

/**
 * In-app notifications of the caller (board 16, CL-18): list with read
 * state, unread count for the bell badge, mark one / all as read.
 */
@RestController
@RequestMapping("/api/v1/notifications")
public class NotificationController {
  private final JdbcTemplate db;
  public NotificationController(JdbcTemplate d) { db = d; }

  @GetMapping
  public List<Map<String, Object>> mine() {
    return db.queryForList(
        "select n.id,n.event_type,n.channel,n.template_code,n.status,n.data::text as data,n.sent_at,n.created_at,n.read_at,(n.read_at is null) as unread," +
        "sb.id booking_id,sb.pickup_address,sb.dropoff_address,sb.scheduled_at,sb.status booking_status,sb.passenger_count,sb.baggage_count " +
        "from notifications n left join scheduled_bookings sb on sb.id::text=n.data->>'bookingId' " +
        "where n.user_id=? order by n.created_at desc limit 100",
        CurrentUser.id());
  }

  @GetMapping("/unread-count")
  public Map<String, Object> unreadCount() {
    Long n = db.queryForObject("select count(*) from notifications where user_id=? and read_at is null", Long.class, CurrentUser.id());
    return Map.of("unread", n == null ? 0 : n);
  }

  @PostMapping("/{id}/read")
  public Map<String, Object> read(@PathVariable UUID id) {
    int updated = db.update("update notifications set read_at=coalesce(read_at,now()) where id=? and user_id=?", id, CurrentUser.id());
    if (updated == 0) throw new ApiException(HttpStatus.NOT_FOUND, "NOTIFICATION_NOT_FOUND");
    return unreadCount();
  }

  @PostMapping("/read-all")
  public Map<String, Object> readAll() {
    db.update("update notifications set read_at=now() where user_id=? and read_at is null", CurrentUser.id());
    return unreadCount();
  }
}
