package com.veyra.booking;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.util.*;

@Component
public class BookingMaintenanceScheduler {
  private final JdbcTemplate db;

  public BookingMaintenanceScheduler(JdbcTemplate db){
    this.db=db;
  }

  @Scheduled(fixedDelayString="${veyra.booking-maintenance.poll-ms:60000}")
  @Transactional
  public void closeExpiredOfferWindows(){
    db.update(
        "update driver_offers set status='EXPIRED' " +
        "where status='ACTIVE' and expires_at is not null and expires_at<=now()");

    List<UUID> noOffer=db.queryForList(
        "select sb.id from scheduled_bookings sb " +
        "where sb.status='OPEN_FOR_OFFERS' and sb.offer_window_ends_at<=now() " +
        "and not exists(select 1 from driver_offers o where o.booking_id=sb.id)",
        UUID.class);

    for(UUID id:noOffer){
      int updated=db.update(
          "update scheduled_bookings set status='NO_OFFER',updated_at=now() " +
          "where id=? and status='OPEN_FOR_OFFERS'",
          id);
      if(updated>0) event(id,"booking.no_offer");
    }

    List<UUID> expired=db.queryForList(
        "select sb.id from scheduled_bookings sb " +
        "where sb.status='OFFERS_RECEIVED' and sb.offer_window_ends_at<=now() " +
        "and sb.selected_driver_id is null",
        UUID.class);

    for(UUID id:expired){
      db.update(
          "update driver_offers set status='EXPIRED' where booking_id=? and status='ACTIVE'",
          id);
      int updated=db.update(
          "update scheduled_bookings set status='EXPIRED',updated_at=now() " +
          "where id=? and status='OFFERS_RECEIVED'",
          id);
      if(updated>0) event(id,"booking.expired");
    }
  }

  @Scheduled(fixedDelayString="${veyra.booking-reminders.poll-ms:60000}")
  public void reminders(){
    enqueueReminder(24*60,"BOOKING_REMINDER_24H");
    enqueueReminder(120,"BOOKING_REMINDER_2H");
    enqueueReminder(60,"BOOKING_REMINDER_1H");
    enqueueReminder(15,"BOOKING_REMINDER_15M");
    enqueuePinAvailable();
  }

  private void enqueueReminder(int minutes,String template){
    String windowStart=String.valueOf(Math.max(0,minutes-2));
    String windowEnd=String.valueOf(minutes+2);

    db.update(
        "insert into notifications(user_id,event_type,channel,template_code,dedupe_key,data,scheduled_for) " +
        "select sb.creator_user_id,'booking.reminder','PUSH',?," +
        "'client-'||cast(sb.id as text)||'-'||?," +
        "jsonb_build_object('bookingId',cast(sb.id as text),'reminder',?),now() " +
        "from scheduled_bookings sb " +
        "where sb.status in ('CONFIRMED','DRIVER_EN_ROUTE','DRIVER_ARRIVED') " +
        "and sb.scheduled_at between now()+cast(?||' minutes' as interval) " +
        "and now()+cast(?||' minutes' as interval) " +
        "on conflict(dedupe_key) do nothing",
        template,template,template,windowStart,windowEnd);

    db.update(
        "insert into notifications(user_id,event_type,channel,template_code,dedupe_key,data,scheduled_for) " +
        "select d.user_id,'booking.reminder','PUSH',?," +
        "'driver-'||cast(sb.id as text)||'-'||?," +
        "jsonb_build_object('bookingId',cast(sb.id as text),'reminder',?),now() " +
        "from scheduled_bookings sb join drivers d on d.id=sb.selected_driver_id " +
        "where sb.status in ('CONFIRMED','DRIVER_EN_ROUTE','DRIVER_ARRIVED') " +
        "and sb.scheduled_at between now()+cast(?||' minutes' as interval) " +
        "and now()+cast(?||' minutes' as interval) " +
        "on conflict(dedupe_key) do nothing",
        template,template,template,windowStart,windowEnd);
  }

  private void enqueuePinAvailable(){
    db.update(
        "insert into notifications(user_id,event_type,channel,template_code,dedupe_key,data,scheduled_for) " +
        "select sb.creator_user_id,'pin.available','PUSH','PIN_AVAILABLE'," +
        "'client-'||cast(sb.id as text)||'-pin-available'," +
        "jsonb_build_object('bookingId',cast(sb.id as text)),now() " +
        "from scheduled_bookings sb " +
        "where sb.status in ('CONFIRMED','DRIVER_EN_ROUTE') " +
        "and sb.scheduled_at between now()+interval '58 minutes' and now()+interval '62 minutes' " +
        "on conflict(dedupe_key) do nothing");
  }

  private void event(UUID bookingId,String type){
    db.update(
        "insert into outbox_events(aggregate_type,aggregate_id,event_type,payload) " +
        "values ('BOOKING',?,?,jsonb_build_object('bookingId',cast(? as text)))",
        bookingId,type,bookingId);
  }
}
