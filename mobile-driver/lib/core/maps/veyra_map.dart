import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'route_geometry.dart';

class VeyraMap extends StatefulWidget {
  final LatLng? pickup;
  final LatLng? dropoff;
  final LatLng? driver;
  final double? driverHeading;
  final VeyraRouteGeometry route;
  final double initialZoom;
  final bool showRecenter;
  final String userAgentPackageName;

  const VeyraMap({
    super.key,
    this.pickup,
    this.dropoff,
    this.driver,
    this.driverHeading,
    this.route=const VeyraRouteGeometry(),
    this.initialZoom=13,
    this.showRecenter=true,
    required this.userAgentPackageName,
  });

  @override
  State<VeyraMap> createState()=>_VeyraMapState();
}

class _VeyraMapState extends State<VeyraMap> {
  final MapController _controller=MapController();
  bool _fitted=false;

  LatLng get _fallback =>
      widget.driver ?? widget.pickup ?? widget.dropoff ?? const LatLng(43.2965,5.3698);

  @override
  void didUpdateWidget(covariant VeyraMap oldWidget){
    super.didUpdateWidget(oldWidget);
    final gainedGeometry=oldWidget.route.points.isEmpty&&widget.route.points.isNotEmpty;
    final gainedDriver=oldWidget.driver==null&&widget.driver!=null;
    if(!_fitted&&(gainedGeometry||gainedDriver)){
      WidgetsBinding.instance.addPostFrameCallback((_){
        if(mounted)_fitAll();
      });
    }
  }

  void _fitAll(){
    final points=<LatLng>[
      ...widget.route.points,
      if(widget.pickup!=null)widget.pickup!,
      if(widget.dropoff!=null)widget.dropoff!,
      if(widget.driver!=null)widget.driver!,
    ];
    if(points.isEmpty)return;
    try{
      if(points.length==1){
        _controller.move(points.first,15);
      }else{
        _controller.fitCamera(CameraFit.bounds(
          bounds:LatLngBounds.fromPoints(points),
          padding:const EdgeInsets.fromLTRB(40,70,40,170),
          maxZoom:16,
        ));
      }
      _fitted=true;
    }catch(_){
      // MapController may not be attached during the very first frame.
    }
  }

  void _recenter(){
    final target=widget.driver ?? widget.pickup ?? widget.dropoff;
    if(target==null)return;
    try{
      _controller.move(target,15);
    }catch(_){}
  }

  @override
  Widget build(BuildContext context){
    WidgetsBinding.instance.addPostFrameCallback((_){
      if(mounted&&!_fitted)_fitAll();
    });

    final scheme=Theme.of(context).colorScheme;
    return Stack(children:[
      FlutterMap(
        mapController:_controller,
        options:MapOptions(
          initialCenter:_fallback,
          initialZoom:widget.initialZoom,
        ),
        children:[
          TileLayer(
            urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName:widget.userAgentPackageName,
          ),
          if(widget.route.points.length>=2)
            PolylineLayer(polylines:[
              Polyline(
                points:widget.route.points,
                strokeWidth:5,
                color:scheme.primary,
                borderStrokeWidth:2,
                borderColor:Colors.white,
              ),
            ]),
          MarkerLayer(markers:[
            if(widget.pickup!=null)
              Marker(
                point:widget.pickup!,
                width:44,
                height:44,
                child:Container(
                  decoration:BoxDecoration(
                    color:Colors.white,
                    shape:BoxShape.circle,
                    boxShadow:[BoxShadow(color:Colors.black.withValues(alpha:.15),blurRadius:8)],
                  ),
                  child:Icon(Icons.trip_origin,color:scheme.primary,size:30),
                ),
              ),
            if(widget.dropoff!=null)
              Marker(
                point:widget.dropoff!,
                width:46,
                height:46,
                child:Container(
                  decoration:BoxDecoration(
                    color:Colors.white,
                    shape:BoxShape.circle,
                    boxShadow:[BoxShadow(color:Colors.black.withValues(alpha:.15),blurRadius:8)],
                  ),
                  child:const Icon(Icons.location_on,color:Color(0xFFDC2626),size:34),
                ),
              ),
            if(widget.driver!=null)
              Marker(
                point:widget.driver!,
                width:58,
                height:58,
                child:Transform.rotate(
                  angle:((widget.driverHeading??0)*math.pi)/180,
                  child:Container(
                    decoration:BoxDecoration(
                      color:scheme.primary,
                      shape:BoxShape.circle,
                      border:Border.all(color:Colors.white,width:3),
                      boxShadow:[BoxShadow(color:Colors.black.withValues(alpha:.22),blurRadius:10)],
                    ),
                    child:const Icon(Icons.navigation,color:Colors.white,size:30),
                  ),
                ),
              ),
          ]),
        ],
      ),
      if(widget.showRecenter)
        Positioned(
          right:14,
          bottom:78,
          child:Material(
            color:Colors.white,
            shape:const CircleBorder(),
            elevation:3,
            child:IconButton(
              tooltip:'Recentrer',
              onPressed:_recenter,
              icon:Icon(Icons.my_location,color:scheme.primary),
            ),
          ),
        ),
      Positioned(
        right:8,
        bottom:6,
        child:Container(
          padding:const EdgeInsets.symmetric(horizontal:7,vertical:3),
          decoration:BoxDecoration(
            color:Colors.white.withValues(alpha:.88),
            borderRadius:BorderRadius.circular(6),
          ),
          child:const Text('© OpenStreetMap contributors',style:TextStyle(fontSize:9,color:Colors.black54)),
        ),
      ),
    ]);
  }
}
