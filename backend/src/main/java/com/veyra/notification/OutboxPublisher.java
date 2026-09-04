package com.veyra.notification;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import java.util.*;

@Component
public class OutboxPublisher {
  private final JdbcTemplate db;
  public OutboxPublisher(JdbcTemplate db){ this.db=db; }

  @Scheduled(fixedDelayString="${veyra.outbox.poll-ms:2000}")
  public void publish(){
    var rows=db.queryForList("select id,event_type,aggregate_id,payload from outbox_events where published_at is null order by occurred_at asc limit 100");
    for(var row:rows){
      UUID id=(UUID)row.get("id");
      String type=(String)row.get("event_type");
      UUID bookingId=(UUID)row.get("aggregate_id");
      if(type.startsWith("booking.") || type.startsWith("offer.")) scheduleNotifications(type,bookingId);
      db.update("update outbox_events set published_at=now() where id=? and published_at is null",id);
    }
  }

  private void scheduleNotifications(String type, UUID bookingId){
    if("booking.published".equals(type)){
      String sql="insert into notifications(user_id,event_type,channel,template_code,dedupe_key,data) "
        +"select u.id,?,'PUSH','NEW_BOOKING','booking-'||cast(? as text)||'-driver-'||cast(u.id as text),jsonb_build_object('bookingId',cast(? as text)) "
        +"from drivers d join users u on u.id=d.user_id "
        +"where d.status='ACTIVE' and d.kyc_status='APPROVED' and d.marketplace_enabled=true "
        +"on conflict(dedupe_key) do nothing";
      db.update(sql,type,bookingId,bookingId);
    } else if("offer.created".equals(type)){
      String sql="insert into notifications(user_id,event_type,channel,template_code,dedupe_key,data) "
        +"select creator_user_id,?,'PUSH','NEW_OFFER','booking-'||cast(? as text)||'-offer-owner',jsonb_build_object('bookingId',cast(? as text)) "
        +"from scheduled_bookings where id=? on conflict(dedupe_key) do nothing";
      db.update(sql,type,bookingId,bookingId,bookingId);
    } else if("booking.confirmed".equals(type)){
      String sql="insert into notifications(user_id,event_type,channel,template_code,dedupe_key,data) "
        +"select d.user_id,?,'PUSH','OFFER_ACCEPTED','booking-'||cast(? as text)||'-confirmed-driver',jsonb_build_object('bookingId',cast(? as text)) "
        +"from scheduled_bookings sb join drivers d on d.id=sb.selected_driver_id where sb.id=? "
        +"on conflict(dedupe_key) do nothing";
      db.update(sql,type,bookingId,bookingId,bookingId);
    } else if(type.startsWith("booking.status.")){
      String sql="insert into notifications(user_id,event_type,channel,template_code,dedupe_key,data) "
        +"select creator_user_id,?,'PUSH','BOOKING_STATUS','booking-'||cast(? as text)||'-status-'||?,jsonb_build_object('bookingId',cast(? as text),'event',?) "
        +"from scheduled_bookings where id=? on conflict(dedupe_key) do nothing";
      db.update(sql,type,bookingId,type,bookingId,type,bookingId);
    }
  }
}
