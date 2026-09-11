package com.veyra.notification;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.veyra.provider.PushProvider;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Real, missing piece found while investigating "notifications are
 * never received" on mobile: OutboxPublisher correctly creates PENDING
 * rows in the notifications table for real events (booking.published,
 * offer.created, etc.), and FirebasePushProvider correctly initializes
 * against Firebase and can genuinely send a push (confirmed directly
 * from a real production log: PUSH_PROVIDER_FIREBASE_INITIALIZED). But
 * nothing anywhere in the codebase ever actually read a PENDING
 * notifications row and called PushProvider.send() with it -- searched
 * the entire backend for any class injecting PushProvider outside its
 * own implementations, found none. The two correctly-built halves of
 * this pipeline were never actually connected.
 */
@Component
public class NotificationDispatcher {
  private static final Logger log=LoggerFactory.getLogger(NotificationDispatcher.class);
  private final JdbcTemplate db;
  private final PushProvider pushProvider;
  private final ObjectMapper objectMapper;

  public NotificationDispatcher(JdbcTemplate db,PushProvider pushProvider,ObjectMapper objectMapper){
    this.db=db;
    this.pushProvider=pushProvider;
    this.objectMapper=objectMapper;
  }

  @Scheduled(fixedDelayString="${veyra.notifications.poll-ms:3000}")
  public void dispatch(){
    List<Map<String,Object>> rows=db.queryForList(
        "select id,user_id,template_code,data::text as data from notifications " +
        "where channel='PUSH' and status='PENDING' " +
        "and (scheduled_for is null or scheduled_for<=now()) " +
        "order by created_at asc limit 100");

    for(Map<String,Object> row:rows){
      UUID id=(UUID)row.get("id");
      UUID userId=(UUID)row.get("user_id");
      String templateCode=(String)row.get("template_code");
      Map<String,Object> data=parseData(row.get("data"));
      boolean sent=false;
      try{
        sent=pushProvider.send(userId,templateCode,data);
      }catch(Exception e){
        // A single bad notification (unexpected data shape, provider
        // hiccup) must never stop every other queued notification in
        // this batch from being attempted.
        log.warn("NOTIFICATION_DISPATCH_FAILED id={} templateCode={} error={}",id,templateCode,e.toString());
      }
      db.update(
          "update notifications set status=?,sent_at=case when ? then now() else sent_at end where id=?",
          sent?"SENT":"FAILED",sent,id);
    }
  }

  /**
   * The SQL query above casts data::text explicitly, so this always
   * receives a plain String -- deliberately avoiding any direct
   * reference to org.postgresql.util.PGobject, which is only a
   * runtime-scoped dependency in this project (pom.xml) and would not
   * compile if referenced directly here. Same reasoning already applied
   * once this session for the CITEXT email column fix: cast at the SQL
   * level rather than unwrap a driver-specific type in Java.
   */
  private Map<String,Object> parseData(Object raw){
    if(raw==null)return Map.of();
    String json=String.valueOf(raw);
    if(json.isBlank())return Map.of();
    try{
      Map<String,Object> parsed=objectMapper.readValue(json,new com.fasterxml.jackson.core.type.TypeReference<HashMap<String,Object>>(){});
      return parsed==null?Map.of():parsed;
    }catch(Exception e){
      log.warn("NOTIFICATION_DATA_PARSE_FAILED json={} error={}",json,e.toString());
      return Map.of();
    }
  }
}
