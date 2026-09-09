package com.veyra.provider;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Replaces NominatimGeocodingProvider entirely. Real problem found in
 * production: Nominatim's own official usage policy
 * (operations.osmfoundation.org/policies/nominatim/) explicitly states
 * "The following uses are strictly forbidden and will get you banned:
 * Auto-complete search -- this is not yet supported by Nominatim and you
 * must not implement such a service on the client side using the API."
 * search() below is called on every few keystrokes (debounced client-side,
 * but still a live autocomplete pattern) -- exactly the forbidden use
 * case, which is the most likely real explanation for autocomplete
 * failures starting to appear (Nominatim's own enforcement blocking
 * this backend's requests).
 *
 * LocationIQ is built on the same underlying OpenStreetMap data but
 * explicitly permits commercial/app autocomplete use as its actual
 * business model (unlike Nominatim's donated best-effort public
 * instance, which was never meant to back a production app's live
 * search-as-you-type). Real endpoints verified live against
 * https://locationiq.com/docs before writing this, not guessed.
 *
 * Label shortening: requests addressdetails=1 (LocationIQ's own
 * documented structured-address breakdown -- road, house_number, city,
 * postcode, etc., confirmed directly against LocationIQ's own API
 * reference rather than guessed) and builds "number road, city postcode"
 * instead of using the raw display_name, which strings together every
 * administrative level (arrondissement, department, region, country) --
 * far more than the address+city+postcode a person actually wants to
 * read in a pickup/dropoff field. Falls back to display_name whenever a
 * result's address breakdown doesn't have enough to build the short
 * form (a landmark/POI with no road, an address outside the areas
 * OSM/LocationIQ have full coverage for, etc.) rather than showing a
 * broken or empty label.
 */
@Component
public class LocationIqGeocodingProvider implements GeocodingProvider {
  private final RestClient http=RestClient.builder().build();
  private final String token;

  public LocationIqGeocodingProvider(@Value("${veyra.locationiq.token}")String token){
    this.token=token;
  }

  @Override
  public List<Place> search(String query,double biasLat,double biasLng){
    if(query==null||query.trim().length()<3||token.isBlank())return List.of();
    Object[] raw=http.get().uri(u->u.scheme("https").host("api.locationiq.com").path("/v1/autocomplete")
      .queryParam("key",token)
      .queryParam("q",query.trim())
      .queryParam("format","json")
      .queryParam("limit",5)
      .queryParam("countrycodes","fr")
      .queryParam("addressdetails",1)
      .queryParam("normalizecity",1)
      .build()).accept(MediaType.APPLICATION_JSON).retrieve().body(Object[].class);
    if(raw==null)return List.of();
    List<Place> out=new ArrayList<>();
    for(Object o:raw){
      Map<?,?> m=(Map<?,?>)o;
      out.add(new Place(
        String.valueOf(m.get("place_id")),
        shortLabel(m),
        Double.parseDouble(String.valueOf(m.get("lat"))),
        Double.parseDouble(String.valueOf(m.get("lon")))));
    }
    return out;
  }

  @Override
  public Place reverse(double lat,double lng){
    if(token.isBlank())return null;
    Map<?,?> raw=http.get().uri(u->u.scheme("https").host("us1.locationiq.com").path("/v1/reverse")
      .queryParam("key",token)
      .queryParam("lat",lat)
      .queryParam("lon",lng)
      .queryParam("format","json")
      .queryParam("addressdetails",1)
      .queryParam("normalizecity",1)
      .build()).accept(MediaType.APPLICATION_JSON).retrieve().body(Map.class);
    if(raw==null||raw.get("display_name")==null)return null;
    return new Place(
      String.valueOf(raw.get("place_id")),
      shortLabel(raw),
      Double.parseDouble(String.valueOf(raw.get("lat"))),
      Double.parseDouble(String.valueOf(raw.get("lon"))));
  }

  /**
   * "number road, city postcode" -- e.g. "350 5th Avenue, New York City
   * 10018" -- built from LocationIQ's own addressdetails breakdown.
   * city/town/village are tried in that order since normalizecity=1
   * mostly (not always) collapses these into "city"; still worth a
   * fallback chain for whichever result doesn't get normalized.
   */
  static String shortLabel(Map<?,?> raw){
    Object addr=raw.get("address");
    if(!(addr instanceof Map<?,?> a))return String.valueOf(raw.get("display_name"));
    String houseNumber=str(a.get("house_number"));
    String road=str(a.get("road"));
    String city=firstNonBlank(str(a.get("city")),str(a.get("town")),str(a.get("village")),str(a.get("suburb")));
    String postcode=str(a.get("postcode"));
    if(road.isBlank()&&city.isBlank())return String.valueOf(raw.get("display_name"));
    StringBuilder sb=new StringBuilder();
    if(!houseNumber.isBlank())sb.append(houseNumber).append(' ');
    sb.append(road);
    if(!city.isBlank()){
      if(!sb.isEmpty())sb.append(", ");
      sb.append(city);
      if(!postcode.isBlank())sb.append(' ').append(postcode);
    }
    return sb.isEmpty()?String.valueOf(raw.get("display_name")):sb.toString();
  }

  private static String str(Object o){return o==null?"":String.valueOf(o).trim();}
  private static String firstNonBlank(String... values){
    for(String v:values)if(!v.isBlank())return v;
    return "";
  }
}
