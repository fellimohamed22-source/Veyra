import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

double normalizeHeading(double value){
  var result=value%360;
  if(result<0)result+=360;
  return result;
}

double lerpHeading(double from,double to,double t){
  final a=normalizeHeading(from);
  final b=normalizeHeading(to);
  var delta=(b-a)%360;
  if(delta>180)delta-=360;
  if(delta<-180)delta+=360;
  return normalizeHeading(a+delta*t);
}

double bearingBetween(LatLng from,LatLng to){
  final lat1=from.latitude*math.pi/180;
  final lat2=to.latitude*math.pi/180;
  final deltaLng=(to.longitude-from.longitude)*math.pi/180;
  final y=math.sin(deltaLng)*math.cos(lat2);
  final x=math.cos(lat1)*math.sin(lat2)-
      math.sin(lat1)*math.cos(lat2)*math.cos(deltaLng);
  return normalizeHeading(math.atan2(y,x)*180/math.pi);
}

double resolveHeading({
  required LatLng from,
  required LatLng to,
  double? reportedHeading,
  required double fallbackHeading,
}){
  if(reportedHeading!=null&&reportedHeading.isFinite&&reportedHeading>=0){
    return normalizeHeading(reportedHeading);
  }
  if(from.latitude==to.latitude&&from.longitude==to.longitude){
    return normalizeHeading(fallbackHeading);
  }
  return bearingBetween(from,to);
}

LatLng lerpLatLng(LatLng from,LatLng to,double t)=>LatLng(
  from.latitude+(to.latitude-from.latitude)*t,
  from.longitude+(to.longitude-from.longitude)*t,
);

Duration driverAnimationDuration(LatLng from,LatLng to){
  final lat=(to.latitude-from.latitude)*111320;
  final meanLat=((from.latitude+to.latitude)/2)*math.pi/180;
  final lng=(to.longitude-from.longitude)*111320*math.cos(meanLat);
  final meters=math.sqrt(lat*lat+lng*lng);
  final millis=(350+meters*18).round().clamp(350,1200).toInt();
  return Duration(milliseconds:millis);
}
