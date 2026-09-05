package com.veyra.booking;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.util.*;

@Component
public class OfferWindowScheduler {
  private final JdbcTemplate db;

  public OfferWindowScheduler(JdbcTemplate db){
    this.db=db;
  }

  @Scheduled(fixedDelay=60000)
  @Transactional
  public void closeExpiredWindows(){
    List<UUID> ids=db.queryForList(
        "select id from scheduled_bookings " +
        "where status in ('OPEN_FOR_OFFERS','OFFERS_RECEIVED') " +
        "and offer_window_ends_at is not null and offer_window_ends_at<=now() " +
        "order by offer_window_ends_at asc limit 200",
        UUID.class);

    for(UUID bookingId:ids){
      Integer activeOffers=db.queryForObject(
          "select count(*) from driver_offers where booking_id=? and status='ACTIVE'",
          Integer.class,bookingId);

      String newStatus=(activeOffers==null||activeOffers==0)?"NO_OFFER":"EXPIRED";

      db.update(
          "update driver_offers set status='EXPIRED' " +
          "where booking_id=? and status='ACTIVE'",
          bookingId);

      int updated=db.update(
          "update scheduled_bookings set status=?,updated_at=now() " +
          "where id=? and status in ('OPEN_FOR_OFFERS','OFFERS_RECEIVED')",
          newStatus,bookingId);

      if(updated>0){
        db.update(
            "insert into booking_status_history(booking_id,from_status,to_status,actor_type,reason_code) " +
            "values (?,null,?,'SYSTEM','OFFER_WINDOW_ENDED')",
            bookingId,newStatus);
        db.update(
            "insert into outbox_events(aggregate_type,aggregate_id,event_type,payload) " +
            "values ('BOOKING',?,'booking.status.'||lower(?),jsonb_build_object('bookingId',?::text,'status',?))",
            bookingId,newStatus,bookingId,newStatus);
      }
    }
  }
}
