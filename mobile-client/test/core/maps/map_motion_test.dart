import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:veyra_client/core/maps/map_motion.dart';

void main(){
  test('heading interpolation crosses north using the shortest path',(){
    final halfway=lerpHeading(350,10,.5);
    expect(halfway,closeTo(0,0.001));
  });

  test('bearing follows eastbound movement when sensor heading is unavailable',(){
    const from=LatLng(43.2965,5.3698);
    const to=LatLng(43.2965,5.3798);
    final heading=resolveHeading(
      from:from,
      to:to,
      reportedHeading:-1,
      fallbackHeading:0,
    );
    expect(heading,closeTo(90,1));
  });

  test('reported GPS heading wins when valid',(){
    const from=LatLng(43.2965,5.3698);
    const to=LatLng(43.3065,5.3698);
    final heading=resolveHeading(
      from:from,
      to:to,
      reportedHeading:215,
      fallbackHeading:0,
    );
    expect(heading,215);
  });

  test('position interpolation keeps motion between GPS fixes',(){
    const from=LatLng(43.0,5.0);
    const to=LatLng(44.0,7.0);
    final middle=lerpLatLng(from,to,.5);
    expect(middle.latitude,43.5);
    expect(middle.longitude,6.0);
  });

  test('vehicle animation duration is bounded',(){
    const from=LatLng(43.2965,5.3698);
    expect(driverAnimationDuration(from,from).inMilliseconds,350);
    const far=LatLng(44.0,6.0);
    expect(driverAnimationDuration(from,far).inMilliseconds,1200);
  });
}
