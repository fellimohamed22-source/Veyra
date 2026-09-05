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

  @GetMapping("/reverse")
  public Map<String,Object> reverse(
      @RequestParam double lat,
      @RequestParam double lng){
    GeocodingProvider.Place p=geocoding.reverse(lat,lng);
    if(p==null){
      // Never make the client fall back to raw coordinates -- an empty
      // result is a real, distinct outcome the app must show as "address
      // not found here", not silently substitute lat/lng as if it were
      // an address.
      return Map.of("found",false);
    }
    return Map.of(
      "found",true,
      "providerId",p.providerId(),
      "label",p.label(),
      "lat",p.lat(),
      "lng",p.lng());
  }
}
