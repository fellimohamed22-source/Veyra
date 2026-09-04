package com.veyra.notification;
import com.veyra.security.CurrentUser;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;
import java.util.*;
@RestController
@RequestMapping("/api/v1/notifications")
public class NotificationController {
  private final JdbcTemplate db;
  public NotificationController(JdbcTemplate db){this.db=db;}

  @GetMapping
  public List<Map<String,Object>> mine(){
    return db.queryForList("select id,event_type,channel,template_code,status,data,sent_at,created_at from notifications where user_id=? order by created_at desc limit 100",CurrentUser.id());
  }
}
