package com.veyra.booking;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.List;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * No test existed at all for this scheduler before. Focused
 * specifically on the two new history.record() additions (not a
 * comprehensive test of the whole closeExpiredOfferWindows() method) --
 * both are SYSTEM-actor, automatic transitions, and both are
 * conditional on the UPDATE actually affecting a row (a booking could
 * have already been mutated by a concurrent request between the
 * candidate-id SELECT and this UPDATE, in which case updated==0 and
 * neither the history entry nor the outbox event should fire).
 */
@ExtendWith(MockitoExtension.class)
class BookingMaintenanceSchedulerTest {

  @Mock JdbcTemplate db;
  @Mock BookingStatusHistoryService history;

  private BookingMaintenanceScheduler scheduler() {
    return new BookingMaintenanceScheduler(db, history);
  }

  @Test
  void recordsNoOfferOnlyWhenTheUpdateActuallyAffectedARow() {
    UUID bookingId = UUID.randomUUID();
    when(db.queryForList(contains("and not exists(select 1 from driver_offers"), eq(UUID.class)))
        .thenReturn(List.of(bookingId));
    when(db.queryForList(contains("and sb.selected_driver_id is null"), eq(UUID.class)))
        .thenReturn(List.of());
    when(db.update(contains("status='NO_OFFER'"), eq(bookingId)))
        .thenReturn(1);

    scheduler().closeExpiredOfferWindows();

    verify(history).record(bookingId, "OPEN_FOR_OFFERS", "NO_OFFER", "SYSTEM", null, "OFFER_WINDOW_CLOSED_NO_OFFER");
  }

  @Test
  void doesNotRecordNoOfferWhenTheRaceConditionMeansNothingWasActuallyUpdated() {
    UUID bookingId = UUID.randomUUID();
    when(db.queryForList(contains("and not exists(select 1 from driver_offers"), eq(UUID.class)))
        .thenReturn(List.of(bookingId));
    when(db.queryForList(contains("and sb.selected_driver_id is null"), eq(UUID.class)))
        .thenReturn(List.of());
    when(db.update(contains("status='NO_OFFER'"), eq(bookingId)))
        .thenReturn(0);

    scheduler().closeExpiredOfferWindows();

    verifyNoInteractions(history);
  }

  @Test
  void recordsExpiredOnlyWhenTheUpdateActuallyAffectedARow() {
    UUID bookingId = UUID.randomUUID();
    when(db.queryForList(contains("and not exists(select 1 from driver_offers"), eq(UUID.class)))
        .thenReturn(List.of());
    when(db.queryForList(contains("and sb.selected_driver_id is null"), eq(UUID.class)))
        .thenReturn(List.of(bookingId));
    when(db.update(contains("status='EXPIRED'"), eq(bookingId)))
        .thenReturn(1);

    scheduler().closeExpiredOfferWindows();

    verify(history).record(bookingId, "OFFERS_RECEIVED", "EXPIRED", "SYSTEM", null, "OFFER_WINDOW_CLOSED_NO_SELECTION");
  }
}
