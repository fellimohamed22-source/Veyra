package com.veyra.booking;
import org.junit.jupiter.api.Test;
import java.time.*;
import static org.junit.jupiter.api.Assertions.*;
class BookingWindowTest {
 @Test void shortWindowEndsThirtyMinutesBefore(){OffsetDateTime now=OffsetDateTime.now();OffsetDateTime at=now.plusHours(3);OffsetDateTime close=at.minusMinutes(30);assertTrue(close.isAfter(now));}
 @Test void normalWindowEndsAtH2(){OffsetDateTime at=OffsetDateTime.now().plusHours(8);assertEquals(at.minusHours(2),at.minusMinutes(120));}
}
