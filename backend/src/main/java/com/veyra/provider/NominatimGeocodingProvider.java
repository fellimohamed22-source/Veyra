package com.veyra.provider;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import java.util.*;

@Component
public class NominatimGeocodingProvider implements GeocodingProvider {
  private final RestClient http=RestClient.builder()
    .baseUrl("https://nominatim.openstreetmap.org")
    .defaultHeader("User-Agent","Veyra-MVP/1.0")
    .build();

  @Override
  public List<Place> search(String query,double biasLat,double biasLng){
    if(query==null || query.trim().length()<3) return List.of();
    Object[] raw=http.get().uri(u->u.path("/search")
      .queryParam("q",query.trim())
      .queryParam("format","jsonv2")
      .queryParam("limit",5)
      .queryParam("countrycodes","fr")
      .build()).accept(MediaType.APPLICATION_JSON).retrieve().body(Object[].class);
    if(raw==null) return List.of();
    List<Place> out=new ArrayList<>();
    for(Object o:raw){
      Map<?,?> m=(Map<?,?>)o;
      out.add(new Place(
        String.valueOf(m.get("place_id")),
        String.valueOf(m.get("display_name")),
        Double.parseDouble(String.valueOf(m.get("lat"))),
        Double.parseDouble(String.valueOf(m.get("lon")))));
    }
    return out;
  }
}
