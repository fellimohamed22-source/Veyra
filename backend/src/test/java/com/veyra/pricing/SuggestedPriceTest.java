package com.veyra.pricing;

import com.veyra.provider.RoutingProvider;
import org.junit.jupiter.api.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class SuggestedPriceTest {
  // Illustrative grid for the arithmetic only, not a tariff proposal.
  static final SuggestedPrice.Grid GRID=new SuggestedPrice.Grid(500,150,30,2000,1000);

  @Test void centerIsBasePlusDistancePlusTimeAndRangeRoundsOutwards(){
    // 32 km, 45 min: 500 + 32 x 150 + 45 x 30 = 6 650 -> 66,50 ; +-10 % = 59,85 / 73,15
    var r=SuggestedPrice.compute(GRID,32_000,2_700);
    assertEquals(6650,r.centerMinor());
    assertEquals(5900,r.lowMinor());
    assertEquals(7400,r.highMinor());
  }

  @Test void minimumAppliesToShortTrips(){
    var r=SuggestedPrice.compute(GRID,1_000,120);
    assertEquals(2000,r.centerMinor());
  }

  @Test void zeroSpreadGivesAWholeUnitRangeAroundTheCenter(){
    var r=SuggestedPrice.compute(new SuggestedPrice.Grid(0,100,0,0,0),10_500,0);
    assertEquals(1050,r.centerMinor());
    assertEquals(1000,r.lowMinor());
    assertEquals(1100,r.highMinor());
  }

  @Nested class Endpoint {
    JdbcTemplate db=mock(JdbcTemplate.class);
    RoutingProvider routing=mock(RoutingProvider.class);
    SuggestedPriceController controller=new SuggestedPriceController(db,routing);
    UUID user=UUID.randomUUID(),booking=UUID.randomUUID();

    @BeforeEach void auth(){
      SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(user,null));
      when(db.queryForList(contains("from drivers"),eq(UUID.class),eq(user))).thenReturn(List.of(UUID.randomUUID()));
    }
    @AfterEach void clear(){SecurityContextHolder.clearContext();}

    @Test void noGridRowMeansNoSuggestion(){
      when(db.queryForList(contains("suggested_price_grid"),eq(booking))).thenReturn(List.of());
      assertEquals(false,controller.suggested(booking).get("available"));
      verifyNoInteractions(routing);
    }

    @Test void routingFailureNeverBlocksTheOfferScreen(){
      Map<String,Object> row=new HashMap<>(Map.of("plat",48.86,"plng",2.33,"dlat",48.72,"dlng",2.36,"base_minor",500L,"per_km_minor",150L,"per_minute_minor",30L,"minimum_minor",2000L,"spread_bps",1000,"currency","EUR"));
      when(db.queryForList(contains("suggested_price_grid"),eq(booking))).thenReturn(List.of(row));
      when(routing.route(anyDouble(),anyDouble(),anyDouble(),anyDouble())).thenThrow(new RuntimeException("osrm down"));
      assertEquals(false,controller.suggested(booking).get("available"));
    }

    @Test void suggestionUsesTheRouteDistanceAndDuration(){
      Map<String,Object> row=new HashMap<>(Map.of("plat",48.86,"plng",2.33,"dlat",48.72,"dlng",2.36,"base_minor",500L,"per_km_minor",150L,"per_minute_minor",30L,"minimum_minor",2000L,"spread_bps",1000,"currency","EUR"));
      when(db.queryForList(contains("suggested_price_grid"),eq(booking))).thenReturn(List.of(row));
      when(routing.route(48.86,2.33,48.72,2.36)).thenReturn(new RoutingProvider.Route(32_000,2_700,List.of()));
      var result=controller.suggested(booking);
      assertEquals(true,result.get("available"));
      assertEquals(5900L,result.get("netLowMinor"));
      assertEquals(7400L,result.get("netHighMinor"));
    }
  }
}
