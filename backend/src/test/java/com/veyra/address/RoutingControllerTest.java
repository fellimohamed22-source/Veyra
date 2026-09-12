package com.veyra.address;

import com.veyra.provider.RoutingProvider;
import com.veyra.shared.ApiException;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class RoutingControllerTest {

  @Test
  void estimateReturnsDistanceDurationAndRenderablePoints(){
    RoutingProvider provider=mock(RoutingProvider.class);
    when(provider.route(43.2965,5.3698,43.4389,5.2146))
      .thenReturn(new RoutingProvider.Route(
        26500,
        1800,
        List.of(
          new RoutingProvider.Point(43.2965,5.3698),
          new RoutingProvider.Point(43.3500,5.3000),
          new RoutingProvider.Point(43.4389,5.2146))));

    RoutingController controller=new RoutingController(provider);
    Map<String,Object> result=controller.estimate(43.2965,5.3698,43.4389,5.2146);

    assertEquals(26500,result.get("distanceMeters"));
    assertEquals(1800,result.get("durationSeconds"));
    assertTrue(result.get("points") instanceof List<?>);

    List<?> points=(List<?>)result.get("points");
    assertEquals(3,points.size());
    assertEquals(
      Map.of("lat",43.2965,"lng",5.3698),
      points.getFirst());
  }

  @Test
  void estimateRejectsInvalidCoordinatesBeforeCallingProvider(){
    RoutingProvider provider=mock(RoutingProvider.class);
    RoutingController controller=new RoutingController(provider);

    ApiException ex=assertThrows(
      ApiException.class,
      ()->controller.estimate(91,5.3698,43.4389,5.2146));

    assertEquals("INVALID_COORDINATES",ex.code());
    verifyNoInteractions(provider);
  }
}
