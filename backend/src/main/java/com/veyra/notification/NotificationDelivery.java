package com.veyra.notification;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.veyra.provider.PushProvider;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.util.*;

@Component
public class NotificationDelivery {
  private final JdbcTemplate db;
  private final PushProvider push;
  private final ObjectMapper json;

  public NotificationDelivery(JdbcTemplate db,PushProvider push,ObjectMapper json){
    this.db=db;
    this.push=push;
    this.json=json;
  }

  @Scheduled(fixedDelayString="${veyra.notifications.poll-ms:3000}")
  @Transactional
  public void deliver(){
    List<Map<String,Object>> rows=db.queryForList(
        "select id,user_id,channel,template_code,data::text as data_json,attempt_count " +
        "from notifications " +
        "where status='PENDING' " +
        "and (scheduled_for is null or scheduled_for<=now()) " +
        "and (next_attempt_at is null or next_attempt_at<=now()) " +
        "order by created_at asc limit 100 for update skip locked");

    for(Map<String,Object> row:rows){
      UUID id=(UUID)row.get("id");
      UUID userId=(UUID)row.get("user_id");
      String channel=(String)row.get("channel");
      String template=(String)row.get("template_code");
      int attempts=((Number)row.get("attempt_count")).intValue();

      if("PUSH".equals(channel) && !push.available()){
        db.update(
            "update notifications set status='SKIPPED',last_error='PUSH_PROVIDER_DISABLED' where id=?",
            id);
        continue;
      }

      try{
        Map<String,Object> data=json.readValue(
            (String)row.get("data_json"),
            new TypeReference<Map<String,Object>>(){});
        boolean delivered=!"PUSH".equals(channel) || push.send(userId,template,data);
        if(delivered){
          db.update(
              "update notifications set status='SENT',sent_at=now(),attempt_count=attempt_count+1,last_error=null where id=?",
              id);
        }else{
          retry(id,attempts+1,"PUSH_NOT_DELIVERED");
        }
      }catch(Exception e){
        retry(id,attempts+1,e.getClass().getSimpleName());
      }
    }
  }

  private void retry(UUID id,int attempts,String error){
    if(attempts>=8){
      db.update(
          "update notifications set status='FAILED',attempt_count=?,last_error=? where id=?",
          attempts,truncate(error),id);
      return;
    }
    long delaySeconds=Math.min(900L,15L*(1L<<Math.min(attempts-1,6)));
    db.update(
        "update notifications set attempt_count=?,last_error=?,next_attempt_at=now()+(? * interval '1 second') where id=?",
        attempts,truncate(error),delaySeconds,id);
  }

  private String truncate(String value){
    if(value==null) return null;
    return value.length()<=500?value:value.substring(0,500);
  }
}
