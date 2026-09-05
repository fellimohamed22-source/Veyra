package com.veyra.notification;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
public class ReminderScheduler {
  private final JdbcTemplate db;

  public ReminderScheduler(JdbcTemplate db){
    this.db=db;
  }

  @Scheduled(fixedDelay=60000)
  public void reminders(){
    reminder(1440,"H24");
    reminder(120,"H2");
    reminder(60,"H1");
    reminder(15,"H15");
    pinAvailable();
  }

  private void reminder(int minutes,String code){
    String from=Integer.toString(Math.max(0,minutes-5));
    String to=Integer.toString(minutes+5);

    db.update(
      "insert into notifications(user_id,event_type,channel,template_code,dedupe_key,data,scheduled_for) " +
      "select d.user_id,'booking.reminder','PUSH','DRIVER_BOOKING_REMINDER'," +
      "'driver-reminder-"+code.toLowerCase()+"-'||sb.id," +
      "jsonb_build_object('bookingId',sb.id,'reminder','"+code+"'),now() " +
      "from scheduled_bookings sb join drivers d on d.id=sb.selected_driver_id " +
      "where sb.status in ('CONFIRMED','DRIVER_EN_ROUTE') " +
      "and sb.scheduled_at between now()+interval '"+from+" minutes' and now()+interval '"+to+" minutes' " +
      "on conflict(dedupe_key) do nothing");

    db.update(
      "insert into notifications(user_id,event_type,channel,template_code,dedupe_key,data,scheduled_for) " +
      "select sb.creator_user_id,'booking.reminder','PUSH','CUSTOMER_BOOKING_REMINDER'," +
      "'customer-reminder-"+code.toLowerCase()+"-'||sb.id," +
      "jsonb_build_object('bookingId',sb.id,'reminder','"+code+"'),now() " +
      "from scheduled_bookings sb " +
      "where sb.status in ('CONFIRMED','DRIVER_EN_ROUTE') " +
      "and sb.scheduled_at between now()+interval '"+from+" minutes' and now()+interval '"+to+" minutes' " +
      "on conflict(dedupe_key) do nothing");
  }

  private void pinAvailable(){
    db.update(
      "insert into notifications(user_id,event_type,channel,template_code,dedupe_key,data,scheduled_for) " +
      "select creator_user_id,'pin.available','PUSH','PIN_AVAILABLE'," +
      "'pin-available-'||id,jsonb_build_object('bookingId',id),now() " +
      "from scheduled_bookings where status in ('CONFIRMED','DRIVER_EN_ROUTE') " +
      "and scheduled_at between now()+interval '55 minutes' and now()+interval '65 minutes' " +
      "on conflict(dedupe_key) do nothing");
  }
}
