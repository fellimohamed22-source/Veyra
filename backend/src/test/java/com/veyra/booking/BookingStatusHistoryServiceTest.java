package com.veyra.booking;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.UUID;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class BookingStatusHistoryServiceTest {

  @Mock JdbcTemplate db;

  @Test
  void recordsAllSixColumnsInOrder() {
    UUID bookingId = UUID.randomUUID();
    UUID actorId = UUID.randomUUID();

    new BookingStatusHistoryService(db).record(bookingId, "CONFIRMED", "DRIVER_EN_ROUTE", "DRIVER", actorId, null);

    verify(db).update(
        contains("insert into booking_status_history(booking_id,from_status,to_status,actor_type,actor_id,reason_code)"),
        eq(bookingId), eq("CONFIRMED"), eq("DRIVER_EN_ROUTE"), eq("DRIVER"), eq(actorId), isNull());
  }

  @Test
  void allowsANullFromStatusForTheInitialTransition() {
    UUID bookingId = UUID.randomUUID();

    new BookingStatusHistoryService(db).record(bookingId, null, "OPEN_FOR_OFFERS", "SYSTEM", null, "AUTO_EXPIRED");

    verify(db).update(anyString(), eq(bookingId), isNull(), eq("OPEN_FOR_OFFERS"), eq("SYSTEM"), isNull(), eq("AUTO_EXPIRED"));
  }
}
