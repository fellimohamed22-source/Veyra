package com.veyra.provider;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Primary;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.util.*;

/**
 * DEC-08: Google Maps Platform for address search, reverse geocoding and
 * routes. Each provider uses Google only when GOOGLE_MAPS_API_KEY is set
 * and otherwise delegates to the existing OpenStreetMap-based provider,
 * so nothing changes until the key (and its billing/quotas) is in place.
 * Response parsing is static and unit-tested; live calls need the key.
 */
public final class GoogleMapsProviders {
  private static final Logger log=LoggerFactory.getLogger(GoogleMapsProviders.class);
  private GoogleMapsProviders(){}

  @Component
  @Primary
  public static class Geocoding implements GeocodingProvider {
    private final LocationIqGeocodingProvider fallback;
    private final String key;
    private final RestClient places=RestClient.builder().baseUrl("https://places.googleapis.com").build();
    private final RestClient maps=RestClient.builder().baseUrl("https://maps.googleapis.com").build();

    public Geocoding(LocationIqGeocodingProvider fallback,@Value("${veyra.google.maps-api-key:}") String key){
      this.fallback=fallback;
      this.key=key==null?"":key.trim();
    }

    @Override
    public List<Place> search(String query,double biasLat,double biasLng){
      if(key.isEmpty())return fallback.search(query,biasLat,biasLng);
      if(query==null||query.trim().length()<3)return List.of();
      Map<String,Object> body=new LinkedHashMap<>();
      body.put("textQuery",query.trim());
      body.put("languageCode","fr");
      body.put("regionCode","FR");
      body.put("pageSize",8);
      body.put("locationBias",Map.of("circle",Map.of("center",Map.of("latitude",biasLat,"longitude",biasLng),"radius",50000.0)));
      try{
        Map<?,?> response=places.post().uri("/v1/places:searchText")
            .header("X-Goog-Api-Key",key)
            .header("X-Goog-FieldMask","places.id,places.formattedAddress,places.displayName,places.location")
            .contentType(MediaType.APPLICATION_JSON).body(body).retrieve().body(Map.class);
        return parsePlaces(response);
      }catch(RuntimeException e){
        log.warn("GOOGLE_PLACES_FAILED error={}",e.getClass().getSimpleName());
        return List.of();
      }
    }

    @Override
    public Place reverse(double lat,double lng){
      if(key.isEmpty())return fallback.reverse(lat,lng);
      try{
        Map<?,?> response=maps.get().uri(u->u.path("/maps/api/geocode/json")
            .queryParam("latlng",lat+","+lng).queryParam("language","fr").queryParam("key",key).build())
            .retrieve().body(Map.class);
        return parseReverse(response,lat,lng);
      }catch(RuntimeException e){
        log.warn("GOOGLE_GEOCODE_FAILED error={}",e.getClass().getSimpleName());
        return null;
      }
    }
  }

  @Component
  @Primary
  public static class Routing implements RoutingProvider {
    private final OsrmRoutingProvider fallback;
    private final String key;
    private final RestClient routes=RestClient.builder().baseUrl("https://routes.googleapis.com").build();

    public Routing(OsrmRoutingProvider fallback,@Value("${veyra.google.maps-api-key:}") String key){
      this.fallback=fallback;
      this.key=key==null?"":key.trim();
    }

    @Override
    public Route route(double fromLat,double fromLng,double toLat,double toLng){
      if(key.isEmpty())return fallback.route(fromLat,fromLng,toLat,toLng);
      Map<String,Object> body=new LinkedHashMap<>();
      body.put("origin",Map.of("location",Map.of("latLng",Map.of("latitude",fromLat,"longitude",fromLng))));
      body.put("destination",Map.of("location",Map.of("latLng",Map.of("latitude",toLat,"longitude",toLng))));
      body.put("travelMode","DRIVE");
      body.put("languageCode","fr");
      Map<?,?> response=routes.post().uri("/directions/v2:computeRoutes")
          .header("X-Goog-Api-Key",key)
          .header("X-Goog-FieldMask","routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline")
          .contentType(MediaType.APPLICATION_JSON).body(body).retrieve().body(Map.class);
      return parseRoute(response);
    }
  }

  static List<GeocodingProvider.Place> parsePlaces(Map<?,?> response){
    List<GeocodingProvider.Place> out=new ArrayList<>();
    if(response==null||!(response.get("places") instanceof List<?> list))return out;
    for(Object o:list){
      if(!(o instanceof Map<?,?> p)||!(p.get("location") instanceof Map<?,?> loc))continue;
      if(!(loc.get("latitude") instanceof Number lat)||!(loc.get("longitude") instanceof Number lng))continue;
      String name=p.get("displayName") instanceof Map<?,?> dn?Objects.toString(dn.get("text"),""):"";
      String address=Objects.toString(p.get("formattedAddress"),"");
      // "Aéroport d'Orly, 94390 Orly, France": name first when it adds information.
      String label=!name.isEmpty()&&!address.startsWith(name)?name+", "+address:address;
      out.add(new GeocodingProvider.Place(Objects.toString(p.get("id"),""),label.replaceAll(", France$",""),lat.doubleValue(),lng.doubleValue()));
    }
    return out;
  }

  static GeocodingProvider.Place parseReverse(Map<?,?> response,double lat,double lng){
    if(response==null||!(response.get("results") instanceof List<?> list)||list.isEmpty())return null;
    if(!(list.getFirst() instanceof Map<?,?> r))return null;
    String label=Objects.toString(r.get("formatted_address"),"").replaceAll(", France$","");
    return new GeocodingProvider.Place(Objects.toString(r.get("place_id"),""),label,lat,lng);
  }

  static RoutingProvider.Route parseRoute(Map<?,?> response){
    if(response==null||!(response.get("routes") instanceof List<?> list)||list.isEmpty()||!(list.getFirst() instanceof Map<?,?> r))
      throw new IllegalStateException("ROUTE_NOT_FOUND");
    int distance=r.get("distanceMeters") instanceof Number n?n.intValue():0;
    // Routes API returns durations as "1234s".
    String rawDuration=Objects.toString(r.get("duration"),"0s");
    int seconds=(int)Math.round(Double.parseDouble(rawDuration.replace("s","")));
    String encoded=r.get("polyline") instanceof Map<?,?> pl?Objects.toString(pl.get("encodedPolyline"),""):"";
    return new RoutingProvider.Route(distance,seconds,decodePolyline(encoded));
  }

  /** Google encoded polyline algorithm (precision 1e-5). */
  static List<Map<String,Double>> decodePolyline(String encoded){
    List<Map<String,Double>> points=new ArrayList<>();
    int index=0,lat=0,lng=0;
    while(index<encoded.length()){
      int[] r=next(encoded,index);lat+=r[0];index=r[1];
      r=next(encoded,index);lng+=r[0];index=r[1];
      points.add(Map.of("lat",lat/1e5,"lng",lng/1e5));
    }
    return points;
  }

  private static int[] next(String s,int index){
    int result=0,shift=0,b;
    do{
      b=s.charAt(index++)-63;
      result|=(b&0x1f)<<shift;
      shift+=5;
    }while(b>=0x20&&index<s.length());
    return new int[]{(result&1)!=0?~(result>>1):(result>>1),index};
  }
}
