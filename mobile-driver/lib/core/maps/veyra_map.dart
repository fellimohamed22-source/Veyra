import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'map_motion.dart';
import 'route_geometry.dart';

/// Ride-hailing map used by both Veyra apps.
///
/// Behaviour intentionally mirrors the interaction model users expect from
/// modern ride-hailing apps: the car glides between GPS fixes, rotates using
/// the device heading, the camera follows automatically until the user pans,
/// and the recenter control resumes follow mode.
class VeyraMap extends StatefulWidget {
  final LatLng? pickup;
  final LatLng? dropoff;
  final LatLng? driver;
  final double? driverHeading;
  final VeyraRouteGeometry route;
  final double initialZoom;
  final bool showRecenter;
  final bool followDriver;
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
    this.followDriver=true,
    required this.userAgentPackageName,
  });

  @override
  State<VeyraMap> createState()=>_VeyraMapState();
}

class _VeyraMapState extends State<VeyraMap>
    with SingleTickerProviderStateMixin {
  final MapController _controller=MapController();
  late final AnimationController _motion;

  LatLng? _displayedDriver;
  LatLng? _motionFrom;
  LatLng? _motionTo;
  double _displayedHeading=0;
  double _headingFrom=0;
  double _headingTo=0;
  bool _fitted=false;
  bool _follow=true;
  bool _mapReady=false;

  LatLng get _fallback =>
      widget.driver ?? widget.pickup ?? widget.dropoff ?? const LatLng(43.2965,5.3698);

  @override
  void initState(){
    super.initState();
    _displayedDriver=widget.driver;
    _displayedHeading=normalizeHeading(widget.driverHeading??0);
    _follow=widget.followDriver;
    _motion=AnimationController(vsync:this)
      ..addListener(_onMotionTick);
  }

  @override
  void didUpdateWidget(covariant VeyraMap oldWidget){
    super.didUpdateWidget(oldWidget);

    if(oldWidget.followDriver!=widget.followDriver){
      _follow=widget.followDriver;
    }

    final next=widget.driver;
    if(next!=null){
      final current=_displayedDriver;
      if(current==null){
        setState((){
          _displayedDriver=next;
          _displayedHeading=normalizeHeading(widget.driverHeading??0);
        });
        if(_follow)_followCamera(next);
      }else if(current.latitude!=next.latitude||current.longitude!=next.longitude){
        _motion.stop();
        _motionFrom=current;
        _motionTo=next;
        _headingFrom=_displayedHeading;
        _headingTo=normalizeHeading(widget.driverHeading??_displayedHeading);
        _motion.duration=driverAnimationDuration(current,next);
        _motion.forward(from:0);
      }else if(widget.driverHeading!=null&&
          normalizeHeading(widget.driverHeading!)!=_displayedHeading){
        _headingFrom=_displayedHeading;
        _headingTo=normalizeHeading(widget.driverHeading!);
        _motionFrom=current;
        _motionTo=current;
        _motion.duration=const Duration(milliseconds:300);
        _motion.forward(from:0);
      }
    }else if(_displayedDriver!=null){
      _motion.stop();
      setState(()=>_displayedDriver=null);
    }

    final routeChanged=oldWidget.route.points.length!=widget.route.points.length||
        (widget.route.points.isNotEmpty&&oldWidget.route.points.isNotEmpty&&
         (oldWidget.route.points.first!=widget.route.points.first||
          oldWidget.route.points.last!=widget.route.points.last));
    if(routeChanged&&!_fitted){
      WidgetsBinding.instance.addPostFrameCallback((_){
        if(mounted)_fitAll();
      });
    }
  }

  void _onMotionTick(){
    final from=_motionFrom;
    final to=_motionTo;
    if(from==null||to==null)return;
    final curve=Curves.easeInOutCubic.transform(_motion.value);
    final position=lerpLatLng(from,to,curve);
    final heading=lerpHeading(_headingFrom,_headingTo,curve);
    if(!mounted)return;
    setState((){
      _displayedDriver=position;
      _displayedHeading=heading;
    });
    if(_follow)_followCamera(position);
  }

  void _followCamera(LatLng target){
    if(!_mapReady)return;
    try{
      _controller.move(target,16.2);
    }catch(_){}
  }

  void _fitAll(){
    if(!_mapReady)return;
    final points=<LatLng>[
      ...widget.route.points,
      if(widget.pickup!=null)widget.pickup!,
      if(widget.dropoff!=null)widget.dropoff!,
      if(_displayedDriver!=null)_displayedDriver!,
    ];
    if(points.isEmpty)return;
    try{
      if(points.length==1){
        _controller.move(points.first,16);
      }else{
        _controller.fitCamera(CameraFit.bounds(
          bounds:LatLngBounds.fromPoints(points),
          padding:const EdgeInsets.fromLTRB(54,90,54,210),
          maxZoom:16,
        ));
      }
      _fitted=true;
    }catch(_){}
  }

  void _recenter(){
    _follow=true;
    final driver=_displayedDriver;
    if(driver!=null){
      _followCamera(driver);
      setState((){});
      return;
    }
    _fitAll();
    setState((){});
  }

  @override
  void dispose(){
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context){
    final driver=_displayedDriver;
    WidgetsBinding.instance.addPostFrameCallback((_){
      if(mounted&&_mapReady&&!_fitted)_fitAll();
    });

    return Stack(children:[
      FlutterMap(
        mapController:_controller,
        options:MapOptions(
          initialCenter:_fallback,
          initialZoom:widget.initialZoom,
          onMapReady:(){
            _mapReady=true;
            _fitAll();
          },
          onPositionChanged:(_,hasGesture){
            if(hasGesture&&_follow&&mounted){
              setState(()=>_follow=false);
            }
          },
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
                strokeWidth:9,
                color:Colors.white.withValues(alpha:.96),
              ),
              Polyline(
                points:widget.route.points,
                strokeWidth:5,
                color:const Color(0xFF171717),
              ),
            ]),
          MarkerLayer(markers:[
            if(widget.pickup!=null)
              Marker(
                point:widget.pickup!,
                width:34,
                height:34,
                child:const _PickupMarker(),
              ),
            if(widget.dropoff!=null)
              Marker(
                point:widget.dropoff!,
                width:38,
                height:48,
                alignment:Alignment.topCenter,
                child:const _DestinationMarker(),
              ),
            if(driver!=null)
              Marker(
                point:driver,
                width:58,
                height:58,
                child:Transform.rotate(
                  angle:_displayedHeading*math.pi/180,
                  child:const _VehicleMarker(),
                ),
              ),
          ]),
        ],
      ),
      Positioned(
        top:12,
        right:12,
        child:_MapControl(
          icon:Icons.layers_outlined,
          tooltip:'Carte',
          onPressed:(){},
          enabled:false,
        ),
      ),
      if(widget.showRecenter)
        Positioned(
          right:14,
          bottom:82,
          child:_MapControl(
            icon:_follow?Icons.navigation:Icons.my_location,
            tooltip:'Recentrer',
            onPressed:_recenter,
            enabled:true,
          ),
        ),
      Positioned(
        right:8,
        bottom:6,
        child:Container(
          padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),
          decoration:BoxDecoration(
            color:Colors.white.withValues(alpha:.90),
            borderRadius:BorderRadius.circular(4),
          ),
          child:const Text(
            '© OpenStreetMap',
            style:TextStyle(fontSize:8,color:Color(0xFF6B7280)),
          ),
        ),
      ),
    ]);
  }
}

class _MapControl extends StatelessWidget{
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool enabled;
  const _MapControl({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context)=>Material(
    color:Colors.white,
    elevation:3,
    shadowColor:Colors.black26,
    shape:const CircleBorder(),
    child:IconButton(
      tooltip:tooltip,
      onPressed:enabled?onPressed:null,
      icon:Icon(icon,color:const Color(0xFF171717),size:22),
    ),
  );
}

class _PickupMarker extends StatelessWidget{
  const _PickupMarker();
  @override
  Widget build(BuildContext context)=>Center(
    child:Container(
      width:18,
      height:18,
      decoration:BoxDecoration(
        color:const Color(0xFF171717),
        shape:BoxShape.circle,
        border:Border.all(color:Colors.white,width:4),
        boxShadow:const [BoxShadow(color:Colors.black26,blurRadius:7,offset:Offset(0,2))],
      ),
    ),
  );
}

class _DestinationMarker extends StatelessWidget{
  const _DestinationMarker();
  @override
  Widget build(BuildContext context)=>Column(
    mainAxisSize:MainAxisSize.min,
    children:[
      Container(
        width:28,
        height:28,
        decoration:BoxDecoration(
          color:const Color(0xFF171717),
          borderRadius:BorderRadius.circular(8),
          border:Border.all(color:Colors.white,width:3),
          boxShadow:const [BoxShadow(color:Colors.black26,blurRadius:8,offset:Offset(0,2))],
        ),
        child:const Icon(Icons.stop_rounded,color:Colors.white,size:14),
      ),
      Container(width:2,height:8,color:const Color(0xFF171717)),
    ],
  );
}

/// Compact top-down car. The painter is north-facing; the marker rotates by
/// the GPS heading (0° north, 90° east), so visual orientation is correct.
class _VehicleMarker extends StatelessWidget{
  const _VehicleMarker();
  @override
  Widget build(BuildContext context)=>Container(
    decoration:const BoxDecoration(
      shape:BoxShape.circle,
      color:Colors.white,
      boxShadow:[
        BoxShadow(color:Colors.black26,blurRadius:12,spreadRadius:1,offset:Offset(0,4)),
      ],
    ),
    padding:const EdgeInsets.all(9),
    child:CustomPaint(painter:_VehiclePainter()),
  );
}

class _VehiclePainter extends CustomPainter{
  @override
  void paint(Canvas canvas,Size size){
    final body=Paint()..color=const Color(0xFF171717);
    final glass=Paint()..color=const Color(0xFF9ED0F6);
    final light=Paint()..color=Colors.white;

    final rect=RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width*.22,size.height*.05,size.width*.56,size.height*.90),
      Radius.circular(size.width*.18),
    );
    canvas.drawRRect(rect,body);

    final windshield=RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width*.31,size.height*.20,size.width*.38,size.height*.20),
      Radius.circular(size.width*.08),
    );
    canvas.drawRRect(windshield,glass);

    final rearGlass=RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width*.31,size.height*.58,size.width*.38,size.height*.17),
      Radius.circular(size.width*.07),
    );
    canvas.drawRRect(rearGlass,glass);

    canvas.drawCircle(Offset(size.width*.34,size.height*.10),size.width*.045,light);
    canvas.drawCircle(Offset(size.width*.66,size.height*.10),size.width*.045,light);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate)=>false;
}
