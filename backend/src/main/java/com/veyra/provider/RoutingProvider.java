package com.veyra.provider;
import java.util.*;
public interface RoutingProvider{
  /**
   * Road route. {@code steps}: turn-by-turn instructions (board 12 P8),
   * each {instruction, maneuver, distanceMeters, lat, lng}; empty when the
   * provider gives none.
   */
  record Route(int distanceMeters,int durationSeconds,List<Map<String,Double>> points,List<Map<String,Object>> steps){
    public Route(int distanceMeters,int durationSeconds,List<Map<String,Double>> points){this(distanceMeters,durationSeconds,points,List.of());}
  }
  Route route(double fromLat,double fromLng,double toLat,double toLng);
}
