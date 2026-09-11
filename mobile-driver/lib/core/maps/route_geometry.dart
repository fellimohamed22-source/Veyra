import 'package:latlong2/latlong.dart';

class VeyraRouteGeometry {
  final int? distanceMeters;
  final int? durationSeconds;
  final List<LatLng> points;

  const VeyraRouteGeometry({
    this.distanceMeters,
    this.durationSeconds,
    this.points=const [],
  });

  factory VeyraRouteGeometry.fromApi(Map<String,dynamic>? data){
    if(data==null)return const VeyraRouteGeometry();
    final rawPoints=data['points'];
    final points=<LatLng>[];
    if(rawPoints is List){
      for(final raw in rawPoints){
        if(raw is! Map)continue;
        final lat=raw['lat'];
        final lng=raw['lng'];
        if(lat is num&&lng is num){
          points.add(LatLng(lat.toDouble(),lng.toDouble()));
        }
      }
    }
    return VeyraRouteGeometry(
      distanceMeters:(data['distanceMeters'] as num?)?.toInt(),
      durationSeconds:(data['durationSeconds'] as num?)?.toInt(),
      points:List.unmodifiable(points),
    );
  }
}
