package com.veyra.booking;

import com.veyra.finance.LedgerService;
import com.veyra.security.PinCrypto;
import com.veyra.shared.ApiException;
import org.junit.jupiter.api.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/** DEC-10 / RIDE-01: "arrived" and "start" only within the pickup radius (default 200 m). */
class PickupProximityTest {
  final UUID user=UUID.randomUUID(),driver=UUID.randomUUID(),booking=UUID.randomUUID();
  final JdbcTemplate db=mock(JdbcTemplate.class);
  final PasswordEncoder encoder=mock(PasswordEncoder.class);
  final BookingController controller=new BookingController(db,encoder,mock(PinCrypto.class),mock(LedgerService.class),120,24,60,30,mock(BookingStatusHistoryService.class));
  final Map<String,Object> state=new HashMap<>();

  @BeforeEach void setup(){
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(user,null));
    state.put("selected_driver_id",driver);
    state.put("pin_hash","hash");
    state.put("pin_failed_attempts",0);
    when(db.queryForList(eq("select id from drivers where user_id=?"),eq(UUID.class),eq(user))).thenReturn(List.of(driver));
    when(db.queryForList(contains("from scheduled_bookings where id=? for update"),eq(booking))).thenAnswer(i->List.of(new HashMap<>(state)));
  }
  @AfterEach void cleanup(){SecurityContextHolder.clearContext();}

  @Test void ride01_arrivalFarFromPickupIsRefused(){
    state.put("status","DRIVER_EN_ROUTE");
    when(db.queryForObject(contains("ST_DWithin"),eq(Boolean.class),any(Object[].class))).thenReturn(false);
    assertEquals("TOO_FAR_FROM_PICKUP",assertThrows(ApiException.class,
        ()->controller.arrived(booking,new BookingController.Position(48.9,2.5))).code());
    verify(db,never()).update(eq("update scheduled_bookings set status=?,updated_at=now() where id=?"),any(),any());
  }

  @Test void sentPositionIsCheckedAgainstTheConfiguredRadius(){
    state.put("status","DRIVER_EN_ROUTE");
    when(db.queryForList(contains("from platform_settings"),eq(Long.class),any(Object[].class)))
        .thenAnswer(i->"ride.pickup_radius_meters".equals(i.getArgument(2))?List.of(150L):List.of());
    when(db.queryForObject(contains("ST_DWithin"),eq(Boolean.class),any(Object[].class))).thenReturn(true);
    controller.arrived(booking,new BookingController.Position(48.0,2.0));
    // longitude first for ST_MakePoint, then latitude, then radius in metres
    verify(db).queryForObject(contains("ST_DWithin"),eq(Boolean.class),eq(2.0),eq(48.0),eq(150L),eq(booking));
    verify(db).update(eq("update scheduled_bookings set status=?,updated_at=now() where id=?"),eq("DRIVER_ARRIVED"),eq(booking));
  }

  @Test void withoutAnyRecentPositionTheTransitionIsRefused(){
    state.put("status","DRIVER_EN_ROUTE");
    when(db.queryForList(contains("current_driver_locations"),eq(Boolean.class),any(Object[].class))).thenReturn(List.of());
    assertEquals("DRIVER_LOCATION_REQUIRED",assertThrows(ApiException.class,()->controller.arrived(booking,null)).code());
  }

  @Test void remoteStartIsRefusedBeforeConsumingAPinAttempt(){
    state.put("status","DRIVER_ARRIVED");
    when(db.queryForObject(contains("ST_DWithin"),eq(Boolean.class),any(Object[].class))).thenReturn(false);
    assertEquals("TOO_FAR_FROM_PICKUP",assertThrows(ApiException.class,
        ()->controller.start(booking,new BookingController.Pin("0427",48.9,2.5))).code());
    verify(encoder,never()).matches(any(),any());
    verify(db,never()).update(contains("pin_failed_attempts=?"),any(),any(),any());
  }
}
