import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/core/maps/route_geometry.dart';

void main(){
  test('parses backend route points in order',(){
    final route=VeyraRouteGeometry.fromApi({
      'distanceMeters':12500,
      'durationSeconds':900,
      'points':[
        {'lat':43.1,'lng':5.1},
        {'lat':43.2,'lng':5.2},
      ],
    });

    expect(route.distanceMeters,12500);
    expect(route.durationSeconds,900);
    expect(route.points.length,2);
    expect(route.points.first.latitude,43.1);
    expect(route.points.last.longitude,5.2);
  });

  test('ignores malformed route points safely',(){
    final route=VeyraRouteGeometry.fromApi({
      'points':[
        {'lat':'bad','lng':5.1},
        {'lat':43.2},
        {'lat':43.3,'lng':5.3},
      ],
    });

    expect(route.points.length,1);
    expect(route.points.single.latitude,43.3);
  });
}
