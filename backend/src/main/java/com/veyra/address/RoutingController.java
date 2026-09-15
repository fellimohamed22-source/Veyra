package com.veyra.address;

import com.veyra.provider.RoutingProvider;
import com.veyra.shared.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

import java.util.*;

@RestController
@RequestMapping("/api/v1/routes")
public class RoutingController {
  private final RoutingProvider routing;

  public RoutingController(RoutingProvider routing){
    this.routing=routing;
  }

  @GetMapping("/estimate")
  public Map<String,Object> estimate(
      @RequestParam double fromLat,
      @RequestParam double fromLng,
      @RequestParam double toLat,
      @RequestParam double toLng){
    validateCoordinates(fromLat,fromLng);
    validateCoordinates(toLat,toLng);

    RoutingProvider.Route route=routing.route(fromLat,fromLng,toLat,toLng);
    Map<String,Object> result=new LinkedHashMap<>();
    result.put("distanceMeters",route.distanceMeters());
    result.put("durationSeconds",route.durationSeconds());
    result.put("points",route.points().stream()
      .map(point->Map.<String,Object>of("lat",point.lat(),"lng",point.lng()))
      .toList());
    return result;
  }

  private void validateCoordinates(double lat,double lng){
    if(!Double.isFinite(lat)||!Double.isFinite(lng)||
        lat < -90 || lat > 90 || lng < -180 || lng > 180){
      throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"INVALID_COORDINATES");
    }
  }
}
