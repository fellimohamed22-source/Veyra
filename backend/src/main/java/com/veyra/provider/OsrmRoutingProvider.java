package com.veyra.provider;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.util.*;

@Component
public class OsrmRoutingProvider implements RoutingProvider {
  private final RestClient http;

  public OsrmRoutingProvider(
      RestClient.Builder builder,
      @Value("${veyra.routing.osrm-base-url:https://router.project-osrm.org}") String baseUrl){
    this.http=builder.baseUrl(baseUrl).build();
  }

  @Override
  public Route route(double fromLat,double fromLng,double toLat,double toLng){
    Map<?,?> body=http.get()
      .uri("/route/v1/driving/"+fromLng+","+fromLat+";"+toLng+","+toLat+
          "?overview=simplified&geometries=geojson&steps=false")
      .retrieve()
      .body(Map.class);

    if(body==null || !(body.get("routes") instanceof List<?> routes) || routes.isEmpty()){
      throw new IllegalStateException("ROUTE_NOT_FOUND");
    }

    Map<?,?> route=(Map<?,?>)routes.getFirst();
    List<Point> points=parseGeometry(route.get("geometry"));

    return new Route(
      ((Number)route.get("distance")).intValue(),
      ((Number)route.get("duration")).intValue(),
      points);
  }

  private List<Point> parseGeometry(Object rawGeometry){
    if(!(rawGeometry instanceof Map<?,?> geometry) ||
        !(geometry.get("coordinates") instanceof List<?> coordinates)){
      return List.of();
    }

    List<Point> points=new ArrayList<>(coordinates.size());
    for(Object raw:coordinates){
      if(!(raw instanceof List<?> pair) || pair.size()<2) continue;
      Object lng=pair.get(0);
      Object lat=pair.get(1);
      if(lng instanceof Number lngNumber && lat instanceof Number latNumber){
        points.add(new Point(latNumber.doubleValue(),lngNumber.doubleValue()));
      }
    }
    return List.copyOf(points);
  }
}
