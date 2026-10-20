
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'veyra_map_marks.dart';
import 'veyra_tiles.dart';
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
  final VeyraRouteGeometry secondaryRoute;
  final double initialZoom;
  final bool showRecenter;
  final bool followDriver;
  final String userAgentPackageName;
  /// Place names next to the marks (boards 10 P4, 12 P8).
  final String? pickupLabel;
  final String? dropoffLabel;
  /// Distance from the bottom edge for the map buttons and the attribution
  /// (a bottom panel may cover the map).
  final double controlsBottom;

  const VeyraMap({
    super.key,
    this.pickup,
    this.dropoff,
    this.driver,
    this.driverHeading,
    this.route=const VeyraRouteGeometry(),
    this.secondaryRoute=const VeyraRouteGeometry(),
    this.initialZoom=13,
    this.showRecenter=true,
    this.followDriver=true,
    required this.userAgentPackageName,
    this.pickupLabel,
    this.dropoffLabel,
    this.controlsBottom=24,
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
        _headingTo=resolveHeading(
          from:current,
          to:next,
          reportedHeading:widget.driverHeading,
          fallbackHeading:_displayedHeading,
        );
        _motion.duration=driverAnimationDuration(current,next);
        _motion.forward(from:0);
      }else if(widget.driverHeading!=null&&
          widget.driverHeading!.isFinite&&
          widget.driverHeading!>=0&&
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

    final routeChanged=
        oldWidget.route.points.length!=widget.route.points.length||
        oldWidget.secondaryRoute.points.length!=widget.secondaryRoute.points.length||
        (widget.route.points.isNotEmpty&&oldWidget.route.points.isNotEmpty&&
         (oldWidget.route.points.first!=widget.route.points.first||
          oldWidget.route.points.last!=widget.route.points.last))||
        (widget.secondaryRoute.points.isNotEmpty&&oldWidget.secondaryRoute.points.isNotEmpty&&
         (oldWidget.secondaryRoute.points.first!=widget.secondaryRoute.points.first||
          oldWidget.secondaryRoute.points.last!=widget.secondaryRoute.points.last));
    if(routeChanged&&_follow){
      _fitted=false;
      WidgetsBinding.instance.addPostFrameCallback((_){
        if(mounted&&_follow)_fitAll();
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
      ...widget.secondaryRoute.points,
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
          padding:EdgeInsets.fromLTRB(54,widget.controlsBottom>24?170:90,64,widget.controlsBottom>24?widget.controlsBottom+40:60),
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

  void _showOverview(){
    _follow=false;
    _fitted=false;
    _fitAll();
    if(mounted)setState((){});
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
          VeyraTiles.layer(widget.userAgentPackageName),
          if(widget.secondaryRoute.points.length>=2)
            PolylineLayer(polylines:[
              Polyline(
                points:widget.secondaryRoute.points,
                strokeWidth:10,
                color:Colors.white.withValues(alpha:.96),
              ),
              Polyline(
                points:widget.secondaryRoute.points,
                strokeWidth:6,
                color:const Color(0xFF94A3B8),
              ),
            ]),
          if(widget.route.points.length>=2)VeyraMapMarks.route(widget.route.points),
          MarkerLayer(markers:[
            if(widget.pickup!=null)VeyraMapMarks.origin(widget.pickup!,label:widget.pickupLabel),
            if(widget.dropoff!=null)VeyraMapMarks.destination(widget.dropoff!,label:widget.dropoffLabel),
            if(driver!=null)VeyraMapMarks.car(driver,heading:_displayedHeading),
          ]),
        ],
      ),
      Positioned(
        right:14,
        bottom:widget.controlsBottom+(widget.showRecenter?60:0),
        child:VeyraMapButton(
          icon:Icons.route_rounded,
          tooltip:'Voir tout le trajet',
          onPressed:_showOverview,
        ),
      ),
      if(widget.showRecenter)
        Positioned(
          right:14,
          bottom:widget.controlsBottom,
          child:VeyraMapButton(
            icon:_follow?Icons.navigation:Icons.my_location,
            tooltip:'Recentrer',
            onPressed:_recenter,
          ),
        ),
      Positioned.fill(child:Padding(
        padding:EdgeInsets.only(bottom:widget.controlsBottom>24?widget.controlsBottom-18:0),
        child:Stack(children:[VeyraTiles.attribution()]),
      )),
    ]);
  }
}

