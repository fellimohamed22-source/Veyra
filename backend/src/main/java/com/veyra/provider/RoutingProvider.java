package com.veyra.provider;

import java.util.List;

public interface RoutingProvider {
  record Point(double lat,double lng){}
  record Route(int distanceMeters,int durationSeconds,List<Point> points){}

  Route route(double fromLat,double fromLng,double toLat,double toLng);
}
