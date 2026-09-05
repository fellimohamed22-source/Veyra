package com.veyra.address;

import com.veyra.provider.RoutingProvider;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

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
    RoutingProvider.Route route=routing.route(fromLat,fromLng,toLat,toLng);
    return Map.of(
        "distanceMeters",route.distanceMeters(),
        "durationSeconds",route.durationSeconds());
  }
}
