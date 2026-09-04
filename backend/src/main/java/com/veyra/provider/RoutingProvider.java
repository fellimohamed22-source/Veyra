package com.veyra.provider;
public interface RoutingProvider {
  record Route(int distanceMeters,int durationSeconds,String geometry){}
  Route route(double fromLat,double fromLng,double toLat,double toLng);
}
