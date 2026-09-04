package com.veyra.provider;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import java.util.*;

@Component
public class OsrmRoutingProvider implements RoutingProvider {
  private final RestClient http=RestClient.builder().baseUrl("https://router.project-osrm.org").build();

  @Override
  public Route route(double fromLat,double fromLng,double toLat,double toLng){
    Map<?,?> body=http.get().uri("/route/v1/driving/"+fromLng+","+fromLat+";"+toLng+","+toLat+"?overview=false")
      .retrieve().body(Map.class);
    if(body==null || !(body.get("routes") instanceof List<?> routes) || routes.isEmpty())
      throw new IllegalStateException("ROUTE_NOT_FOUND");
    Map<?,?> r=(Map<?,?>)routes.getFirst();
    return new Route(
      ((Number)r.get("distance")).intValue(),
      ((Number)r.get("duration")).intValue(),
      null);
  }
}
