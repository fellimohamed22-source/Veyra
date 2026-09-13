package com.veyra.location;

import com.veyra.shared.ApiException;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class LocationControllerTest {

  @Mock JdbcTemplate db;
  @Mock SimpMessagingTemplate ws;

  @AfterEach
  void clearSecurityContext(){
    SecurityContextHolder.clearContext();
  }

  private LocationController controller(UUID userId,UUID driverId,UUID bookingId){
    SecurityContextHolder.getContext().setAuthentication(
        new TestingAuthenticationToken(userId,null,"ROLE_DRIVER"));
    when(db.queryForObject(contains("select id from drivers"),eq(UUID.class),eq(userId)))
        .thenReturn(driverId);
    when(db.queryForObject(contains("select count(*) from scheduled_bookings"),eq(Integer.class),eq(bookingId),eq(driverId)))
        .thenReturn(1);
    return new LocationController(db,ws);
  }

  @Test
  void freshFixAfterAppRestartIsAcceptedEvenWithLowerSequence(){
    UUID userId=UUID.randomUUID();
    UUID driverId=UUID.randomUUID();
    UUID bookingId=UUID.randomUUID();
    OffsetDateTime oldTime=OffsetDateTime.now().minusMinutes(2);
    OffsetDateTime newTime=OffsetDateTime.now();

    when(db.queryForList(contains("select booking_id,sequence_no,recorded_at"),eq(driverId)))
        .thenReturn(List.of(Map.of(
            "booking_id",bookingId,
            "sequence_no",999999L,
            "recorded_at",oldTime)));
    when(db.update(contains("insert into current_driver_locations"),any(Object[].class)))
        .thenReturn(1);

    LocationController controller=controller(userId,driverId,bookingId);
    LocationController.Pos pos=new LocationController.Pos(
        bookingId,43.2965,5.3698,5.0,90.0,8.0,1L,newTime);

    assertDoesNotThrow(()->controller.update(pos));
    verify(ws).convertAndSend(eq("/topic/bookings/"+bookingId+"/location"),eq(pos));
  }

  @Test
  void genuinelyOlderFixWithLowerSequenceIsRejected(){
    UUID userId=UUID.randomUUID();
    UUID driverId=UUID.randomUUID();
    UUID bookingId=UUID.randomUUID();
    OffsetDateTime oldTime=OffsetDateTime.now();
    OffsetDateTime replayTime=oldTime.minusSeconds(10);

    when(db.queryForList(contains("select booking_id,sequence_no,recorded_at"),eq(driverId)))
        .thenReturn(List.of(Map.of(
            "booking_id",bookingId,
            "sequence_no",50L,
            "recorded_at",oldTime)));

    LocationController controller=controller(userId,driverId,bookingId);
    LocationController.Pos pos=new LocationController.Pos(
        bookingId,43.2965,5.3698,5.0,90.0,8.0,49L,replayTime);

    ApiException ex=assertThrows(ApiException.class,()->controller.update(pos));
    assertEquals("LOCATION_REPLAY",ex.code());
    verify(db,never()).update(contains("insert into current_driver_locations"),any(Object[].class));
    verifyNoInteractions(ws);
  }

  @Test
  void locationFromAnotherBookingStartsANewSequenceScope(){
    UUID userId=UUID.randomUUID();
    UUID driverId=UUID.randomUUID();
    UUID bookingId=UUID.randomUUID();
    UUID previousBookingId=UUID.randomUUID();
    OffsetDateTime now=OffsetDateTime.now();

    when(db.queryForList(contains("select booking_id,sequence_no,recorded_at"),eq(driverId)))
        .thenReturn(List.of(Map.of(
            "booking_id",previousBookingId,
            "sequence_no",Long.MAX_VALUE,
            "recorded_at",now)));
    when(db.update(contains("insert into current_driver_locations"),any(Object[].class)))
        .thenReturn(1);

    LocationController controller=controller(userId,driverId,bookingId);
    LocationController.Pos pos=new LocationController.Pos(
        bookingId,43.2965,5.3698,5.0,90.0,8.0,1L,now);

    assertDoesNotThrow(()->controller.update(pos));
  }
}
