package com.veyra.notification;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import java.util.*;
@Component
public class NotificationDelivery {
  private final JdbcTemplate db;
  public NotificationDelivery(JdbcTemplate db){this.db=db;}

  @Scheduled(fixedDelayString = "${veyra.notifications.poll-ms:3000}")
  public void deliverInApp(){
    var rows=db.queryForList("select id from notifications where status='PENDING' order by created_at asc limit 100");
    for(var row:rows){
      db.update("update notifications set status='SENT',sent_at=now() where id=? and status='PENDING'",row.get("id"));
    }
  }
}
