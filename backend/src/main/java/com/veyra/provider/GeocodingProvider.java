package com.veyra.provider;
import java.util.List;
public interface GeocodingProvider {
  record Place(String providerId,String label,double lat,double lng){}
  List<Place> search(String query,double biasLat,double biasLng);
}
