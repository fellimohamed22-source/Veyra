package com.veyra.address;

import com.veyra.provider.GeocodingProvider;
import org.springframework.web.bind.annotation.*;
import java.util.*;

@RestController
@RequestMapping("/api/v1/addresses")
public class AddressController {
  private final GeocodingProvider geocoding;
  public AddressController(GeocodingProvider geocoding){ this.geocoding=geocoding; }

  @GetMapping("/autocomplete")
  public List<Map<String,Object>> search(
      @RequestParam String q,
      @RequestParam(defaultValue="43.2965") double biasLat,
      @RequestParam(defaultValue="5.3698") double biasLng){
    return geocoding.search(q,biasLat,biasLng).stream()
      .map(p->Map.<String,Object>of(
        "providerId",p.providerId(),
        "label",p.label(),
        "lat",p.lat(),
        "lng",p.lng()))
      .toList();
  }
}
