package com.veyra.notification;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.*;

/**
 * Gap found while tracing the full offer.created -> NEW_OFFER -> push
 * pipeline (NotificationDispatcher already got the same treatment):
 * this class had zero logging at all, on any path. Firebase
 * initializing successfully and NotificationDispatcher never once
 * logging NOTIFICATION_DISPATCH_RUN after a real offer submission
 * points at the break being here or earlier -- but that could not be
 * confirmed or ruled out without this.
 */
@Component
public class OutboxPublisher {
  private static final Logger log=LoggerFactory.getLogger(OutboxPublisher.class);
  private final JdbcTemplate db;

  public OutboxPublisher(JdbcTemplate db){
    this.db=db;
  }

  @Scheduled(fixedDelayString="${veyra.outbox.poll-ms:2000}")
  public void publish(){
    List<Map<String,Object>> rows=db.queryForList(
        "select id,event_type,aggregate_id,payload from outbox_events " +
        "where published_at is null order by occurred_at asc limit 100");

    // Same reasoning as NotificationDispatcher's own fix: never log on
    // an empty poll (this runs every 2s by default -- would spam the
    // logs forever), only when there's genuinely something to report.
    // Deliberately never logs `payload` itself, per the explicit "do
    // not log sensitive payloads" instruction -- only the event type
    // and the booking/aggregate id, which are not sensitive on their
    // own.
    if(rows.isEmpty())return;

    for(Map<String,Object> row:rows){
      UUID eventId=(UUID)row.get("id");
      String type=(String)row.get("event_type");
      UUID bookingId=(UUID)row.get("aggregate_id");

      if(type.startsWith("booking.")||type.startsWith("offer.")){
        int notificationsInserted=scheduleNotifications(eventId,type,bookingId);
        log.info("OUTBOX_EVENT_PROCESSED eventId={} type={} bookingId={} notificationsInserted={}",
            eventId,type,bookingId,notificationsInserted);
      }else{
        log.info("OUTBOX_EVENT_IGNORED eventId={} type={} bookingId={} reason=unmapped_event_type",
            eventId,type,bookingId);
      }

      db.update(
          "update outbox_events set published_at=now() where id=? and published_at is null",
          eventId);
    }
  }

  /**
   * Returns how many notifications rows this event actually inserted
   * (0 or 1 for offer.created/booking.confirmed; 0 or more for
   * booking.published, which fans out to every eligible driver) --
   * purely so publish() can log it. ON CONFLICT DO NOTHING means this
   * can legitimately be 0 even on a correctly-matched event (a genuine
   * duplicate dedupe_key), which is itself useful to see in the log
   * rather than silently indistinguishable from "nothing matched at
   * all."
   */
  private int scheduleNotifications(UUID eventId,String type,UUID bookingId){
    if("booking.published".equals(type)){
      return db.update(
          "insert into notifications(user_id,event_type,channel,template_code,dedupe_key,data) " +
          "select u.id,?,'PUSH','NEW_BOOKING'," +
          "'event-'||cast(? as text)||'-driver-'||cast(u.id as text)," +
          "jsonb_build_object('bookingId',cast(? as text)) " +
          "from drivers d join users u on u.id=d.user_id " +
          "where d.status='ACTIVE' and d.kyc_status='APPROVED' and d.marketplace_enabled=true " +
          "on conflict(dedupe_key) do nothing",
          type,eventId,bookingId);
    }

    if("offer.created".equals(type)){
      return db.update(
          "insert into notifications(user_id,event_type,channel,template_code,dedupe_key,data) " +
          "select creator_user_id,?,'PUSH','NEW_OFFER'," +
          "'event-'||cast(? as text)||'-offer-owner'," +
          "jsonb_build_object('bookingId',cast(? as text)) " +
          "from scheduled_bookings where id=? " +
          "on conflict(dedupe_key) do nothing",
          type,eventId,bookingId,bookingId);
    }

    if("booking.confirmed".equals(type)){
      return db.update(
          "insert into notifications(user_id,event_type,channel,template_code,dedupe_key,data) " +
          "select d.user_id,?,'PUSH','OFFER_ACCEPTED'," +
          "'booking-'||cast(? as text)||'-confirmed-driver'," +
          "jsonb_build_object('bookingId',cast(? as text)) " +
          "from scheduled_bookings sb join drivers d on d.id=sb.selected_driver_id where sb.id=? " +
          "on conflict(dedupe_key) do nothing",
          type,bookingId,bookingId,bookingId);
    }

    if(type.startsWith("booking.status.") ||
        "booking.no_offer".equals(type) ||
        "booking.expired".equals(type) ||
        "booking.driver_cancelled".equals(type)){
      return db.update(
          "insert into notifications(user_id,event_type,channel,template_code,dedupe_key,data) " +
          "select creator_user_id,?,'PUSH','BOOKING_STATUS'," +
          "'event-'||cast(? as text)||'-owner'," +
          "jsonb_build_object('bookingId',cast(? as text),'event',?) " +
          "from scheduled_bookings where id=? " +
          "on conflict(dedupe_key) do nothing",
          type,eventId,bookingId,type,bookingId);
    }

    return 0;
  }
}
