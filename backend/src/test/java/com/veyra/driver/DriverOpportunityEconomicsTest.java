package com.veyra.driver;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class DriverOpportunityEconomicsTest {
  @Mock JdbcTemplate db;
  private final UUID userId=UUID.randomUUID();
  private final UUID driverId=UUID.randomUUID();
  private final UUID bookingId=UUID.randomUUID();

  @AfterEach void clear(){ SecurityContextHolder.clearContext(); }

  private void common(){
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(userId,null));
    when(db.queryForList(eq("select id from drivers where user_id=?"),eq(UUID.class),eq(userId))).thenReturn(List.of(driverId));
    when(db.queryForObject(contains("from drivers where id=? and status='ACTIVE'"),eq(Integer.class),eq(driverId))).thenReturn(1);
    Map<String,Object> booking=new HashMap<>();
    booking.put("id",bookingId);
    booking.put("trip_distance_meters",18400L);
    when(db.queryForList(contains("from scheduled_bookings sb join vehicle_categories"),eq(bookingId))).thenReturn(List.of(booking));
    when(db.queryForList(contains("select proposed_amount_minor from driver_offers"),eq(bookingId),eq(driverId))).thenReturn(List.of());
  }

  @Test void returnsApproachDistanceAndLowestCompetingOfferTogether(){
    common();
    when(db.queryForList(contains("ST_MakePoint(cdl.lng,cdl.lat)"),eq(bookingId),eq(driverId)))
        .thenReturn(List.of(Map.of("approach_distance_meters",3200L)));
    when(db.queryForObject(contains("select min(proposed_amount_minor)"),eq(Long.class),eq(bookingId),eq(driverId)))
        .thenReturn(4200L);

    Map<String,Object> result=new DriverOpportunityController(db).detail(bookingId);

    assertEquals(18400L,result.get("trip_distance_meters"));
    assertEquals(3200L,result.get("approach_distance_meters"));
    assertEquals(4200L,result.get("currentBestOtherOfferMinor"));
    assertEquals(true,result.get("competitorBenchmarkVisible"));
    assertEquals("DRIVER",result.get("pricingDecisionOwner"));
    assertEquals("MARKET_BENCHMARK_AND_JOB_ECONOMICS",result.get("pricingGuidance"));
  }

  @Test void noCompetitorIsRepresentedByNullWithoutBlockingEconomics(){
    common();
    when(db.queryForList(contains("ST_MakePoint(cdl.lng,cdl.lat)"),eq(bookingId),eq(driverId))).thenReturn(List.of());
    when(db.queryForObject(contains("select min(proposed_amount_minor)"),eq(Long.class),eq(bookingId),eq(driverId))).thenReturn(null);

    Map<String,Object> result=new DriverOpportunityController(db).detail(bookingId);

    assertEquals(18400L,result.get("trip_distance_meters"));
    assertNull(result.get("currentBestOtherOfferMinor"));
    assertEquals(true,result.get("competitorBenchmarkVisible"));
  }
}
