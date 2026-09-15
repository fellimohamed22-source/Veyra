import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/core/maps/route_geometry.dart';

void main(){
  test('parses backend route geometry for driver map',(){
    final route=VeyraRouteGeometry.fromApi({
      'distanceMeters':4200,
      'durationSeconds':480,
      'points':[
        {'lat':43.29,'lng':5.36},
        {'lat':43.31,'lng':5.40},
      ],
    });

    expect(route.distanceMeters,4200);
    expect(route.durationSeconds,480);
    expect(route.points.length,2);
    expect(route.points.first.latitude,43.29);
  });
}
