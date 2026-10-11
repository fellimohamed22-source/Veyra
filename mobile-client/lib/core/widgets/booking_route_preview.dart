import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Preview of a *requested* trip, not a driver tracking or price quote.
/// Route metrics are supplied by /api/v1/routes/estimate.
class BookingRoutePreview extends StatelessWidget {
  /// Tests can disable external tile requests while retaining route overlays.
  static bool enableNetworkTiles = true;
  const BookingRoutePreview({
    super.key,
    required this.pickupLat, required this.pickupLng,
    required this.dropoffLat, required this.dropoffLng,
    this.distanceMeters, this.durationSeconds, this.routePoints=const [],
    this.loading=false, this.error, this.onRetry,
  });
  final double pickupLat,pickupLng,dropoffLat,dropoffLng;
  final num? distanceMeters,durationSeconds;
  final List<LatLng> routePoints;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final start=LatLng(pickupLat,pickupLng);
    final end=LatLng(dropoffLat,dropoffLng);
    final center=LatLng((pickupLat+dropoffLat)/2,(pickupLng+dropoffLng)/2);
    final allPoints=[start,end,...routePoints];
    final bounds=LatLngBounds.fromPoints(allPoints);
    final theme=Theme.of(context);
    return Card(
      clipBehavior:Clip.antiAlias,
      child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Padding(
          padding:const EdgeInsets.fromLTRB(16,16,16,8),
          child:Text('Aperçu du trajet',style:theme.textTheme.titleMedium),
        ),
        SizedBox(
          height:210,
          child:FlutterMap(
            options:MapOptions(initialCenter:center,initialZoom:11,
              initialCameraFit:CameraFit.bounds(bounds:bounds,
                padding:const EdgeInsets.all(40))),
            children:[
              if(enableNetworkTiles) TileLayer(
                urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName:'com.veyra.client',
              ),
              if(routePoints.length>=2)PolylineLayer(polylines:[
                Polyline(points:routePoints,strokeWidth:4,color:theme.colorScheme.primary),
              ]),
              MarkerLayer(markers:[
                Marker(point:start,width:48,height:48,
                  child:const Icon(Icons.trip_origin,color:Colors.green,size:34)),
                Marker(point:end,width:48,height:48,
                  child:const Icon(Icons.location_on,color:Colors.red,size:38)),
              ]),
            ],
          ),
        ),
        Padding(
          padding:const EdgeInsets.all(16),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            if(loading) const LinearProgressIndicator(),
            if(error!=null) ...[
              Text(error!,style:TextStyle(color:theme.colorScheme.error)),
              TextButton(onPressed:onRetry,child:const Text('Réessayer')),
            ],
            if(!loading&&error==null&&distanceMeters!=null&&durationSeconds!=null)
              Text('${(distanceMeters!.toDouble()/1000).toStringAsFixed(1)} km • environ ${(durationSeconds!.toDouble()/60).ceil()} min',
                style:theme.textTheme.bodyLarge),
            const SizedBox(height:6),
            const Text('Durée indicative de l’itinéraire, hors trafic et attente du chauffeur. '
              'Le prix sera proposé par les chauffeurs après publication.'),
          ]),
        ),
      ]),
    );
  }
}
