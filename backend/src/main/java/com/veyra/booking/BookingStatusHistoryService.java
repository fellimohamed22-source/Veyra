package com.veyra.booking;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.util.UUID;

/**
 * Gap found while building P32 (Partner "Suivi reservation"):
 * booking_status_history has existed since V001__schema.sql and is read
 * by two different endpoints (SupportController's admin timeline, and
 * BookingQueryController's new partner-scoped one), but nothing
 * anywhere ever wrote to it -- confirmed by grepping the entire backend
 * for any INSERT into this table before starting this change. Both
 * readers have been silently returning empty history this whole time.
 *
 * actor_type values match the existing creator_type convention already
 * used on scheduled_bookings itself (CLIENT/PARTNER, confirmed by
 * reading BookingController's insert), extended with DRIVER/SYSTEM for
 * the transitions those actors cause.
 */
@Service
public class BookingStatusHistoryService {
  private final JdbcTemplate db;

  public BookingStatusHistoryService(JdbcTemplate db){
    this.db=db;
  }

  public void record(UUID bookingId,String fromStatus,String toStatus,String actorType,UUID actorId,String reasonCode){
    db.update(
        "insert into booking_status_history(booking_id,from_status,to_status,actor_type,actor_id,reason_code) values (?,?,?,?,?,?)",
        bookingId,fromStatus,toStatus,actorType,actorId,reasonCode);
  }
}
