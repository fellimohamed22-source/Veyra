import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:latlong2/latlong.dart';

import 'veyra_map_marks.dart';

/// Native Google Maps SDK -- the map engine of Uber and Bolt -- used by
/// every map of the app when the build carries GOOGLE_MAPS_MOBILE_KEY
/// (dart-define, plus the same key in the Android manifest / iOS
/// AppDelegate, see the CI workflows). Tests and keyless builds keep the
/// flutter_map fallback.
const String veyraMapsKey = String.fromEnvironment('GOOGLE_MAPS_MOBILE_KEY');

bool get veyraGoogleMapsEnabled =>
    veyraMapsKey.isNotEmpty &&
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) &&
    !Platform.environment.containsKey('FLUTTER_TEST');

gm.LatLng toGm(LatLng p) => gm.LatLng(p.latitude, p.longitude);
LatLng fromGm(gm.LatLng p) => LatLng(p.latitude, p.longitude);

gm.LatLngBounds boundsOf(List<LatLng> points) {
  var s = points.first.latitude, n = s, w = points.first.longitude, e = w;
  for (final p in points) {
    s = math.min(s, p.latitude);
    n = math.max(n, p.latitude);
    w = math.min(w, p.longitude);
    e = math.max(e, p.longitude);
  }
  // A zero-size box (single point twice) cannot be fitted.
  if (n - s < 1e-4) { n += 5e-4; s -= 5e-4; }
  if (e - w < 1e-4) { e += 5e-4; w -= 5e-4; }
  return gm.LatLngBounds(southwest: gm.LatLng(s, w), northeast: gm.LatLng(n, e));
}

/// Light, quiet base map as in ride-hailing apps: roads and place names
/// stay readable, shops and transit icons are hidden.
const String veyraMapStyle = '''[
  {"elementType":"geometry","stylers":[{"color":"#f3f5f8"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#5b6576"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#ffffff"},{"weight":3}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"visibility":"on"},{"color":"#e2efdf"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#e7eaf0"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#d5dae3"}]},
  {"featureType":"road.local","elementType":"labels.text.fill","stylers":[{"color":"#8a94a6"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#cddcee"}]}
]''';

/// A marker bitmap and the fraction of it that sits on the coordinate.
typedef VeyraIcon = ({gm.BitmapDescriptor icon, Offset anchor});

/// Marks of the boards drawn once as bitmaps (Google markers are images).
class VeyraMarkerIcons {
  VeyraMarkerIcons._();
  static const double _scale = 3;
  static final Map<String, Future<VeyraIcon>> _cache = {};

  static Future<VeyraIcon> origin(String? label) => _cache.putIfAbsent('o|$label', () => _place(label, destination: false));
  static Future<VeyraIcon> destination(String? label) => _cache.putIfAbsent('d|$label', () => _place(label, destination: true));
  static Future<VeyraIcon> car() => _cache.putIfAbsent('car', _car);
  static Future<VeyraIcon> eta(String text) => _cache.putIfAbsent('e|$text', () => _eta(text));

  static TextPainter _text(String text, {required Color color, double size = 14, int maxLines = 2, double maxWidth = 200, Color? stroke}) {
    final style = TextStyle(fontSize: size, fontWeight: FontWeight.w700, height: 1.15, color: stroke == null ? color : null,
        foreground: stroke == null ? null : (Paint()..style = PaintingStyle.stroke..strokeWidth = 4..color = stroke));
    return TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, maxLines: maxLines, ellipsis: '…')
      ..layout(maxWidth: maxWidth);
  }

  static Future<VeyraIcon> _finish(ui.PictureRecorder recorder, double w, double h, Offset anchor) async {
    final image = await recorder.endRecording().toImage((w * _scale).ceil(), (h * _scale).ceil());
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    return (icon: gm.BitmapDescriptor.bytes(bytes, imagePixelRatio: _scale), anchor: anchor);
  }

  /// Blue ring (start) or red pin (destination), place name on the right.
  static Future<VeyraIcon> _place(String? label, {required bool destination}) async {
    final hasLabel = label != null && label.isNotEmpty;
    final halo = hasLabel ? _text(label, color: Colors.white, maxLines: destination ? 3 : 2, stroke: Colors.white) : null;
    final ink = hasLabel ? _text(label, color: const Color(0xFF0E1A2B), maxLines: destination ? 3 : 2) : null;
    const mark = 40.0;
    final w = mark + (hasLabel ? 8 + ink!.width + 4 : 0);
    final h = math.max(mark + 4, (ink?.height ?? 0) + 8);
    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder)..scale(_scale);
    final cx = mark / 2, cy = h / 2;
    if (destination) {
      final icon = Icons.location_on;
      final tp = TextPainter(
          text: TextSpan(text: String.fromCharCode(icon.codePoint), style: TextStyle(fontSize: 40, fontFamily: icon.fontFamily, package: icon.fontPackage, color: VeyraMapMarks.pinRed)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(c, Offset(cx - tp.width / 2, cy - tp.height / 2));
    } else {
      c.drawCircle(Offset(cx, cy + 1.5), 10, Paint()..color = Colors.black26..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5));
      c.drawCircle(Offset(cx, cy), 9, Paint()..color = Colors.white);
      c.drawCircle(Offset(cx, cy), 6.5, Paint()..color = VeyraMapMarks.routeBlue..style = PaintingStyle.stroke..strokeWidth = 5);
    }
    if (hasLabel) {
      final at = Offset(mark + 8, cy - ink!.height / 2 - (destination ? 6 : 0));
      halo!.paint(c, at);
      ink.paint(c, at);
    }
    // The pin's tip (destination) or the ring's centre (start) is the point.
    final anchor = destination ? Offset(cx / w, (cy + 17) / h) : Offset(cx / w, cy / h);
    return _finish(recorder, w, h, anchor);
  }

  static Future<VeyraIcon> _car() async {
    const s = 46.0;
    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder)..scale(_scale);
    const VeyraCarPainter().paint(c, const Size(s, s));
    return _finish(recorder, s, s, const Offset(.5, .5));
  }

  static Future<VeyraIcon> _eta(String text) async {
    final tp = _text(text, color: Colors.white, maxLines: 1);
    final w = tp.width + 24, h = tp.height + 12 + 6;
    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder)..scale(_scale);
    final box = RRect.fromRectAndRadius(Rect.fromLTWH(0, 3, w, h - 6), const Radius.circular(10));
    c.drawRRect(box.shift(const Offset(0, 2)), Paint()..color = Colors.black26..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    c.drawRRect(box, Paint()..color = VeyraMapMarks.routeBlue);
    tp.paint(c, Offset(12, 3 + 6));
    return _finish(recorder, w, h, const Offset(.5, .5));
  }
}

/// The map itself, drawn by the Google Maps SDK. [carGlide] animates the
/// car between successive positions (the parent may animate it itself).
class VeyraGoogleMap extends StatefulWidget {
  final LatLng? pickup;
  final LatLng? dropoff;
  final String? pickupLabel;
  final String? dropoffLabel;
  final List<LatLng> route;
  final List<LatLng> secondaryRoute;
  final LatLng? car;
  final double carHeading;
  final bool carGlide;
  final String? etaText;
  final LatLng? etaAt;
  final bool interactive;
  final void Function(LatLng point)? onTap;
  /// Space kept free around the content when the camera frames it.
  final EdgeInsets padding;
  final LatLng initialCenter;
  final double initialZoom;
  /// Frame pickup, destination, route and car once the map is ready.
  final bool fitOnCreate;
  final void Function(gm.GoogleMapController controller)? onCreated;
  /// The user touched the map (stops follow mode).
  final VoidCallback? onUserGesture;

  const VeyraGoogleMap({
    super.key,
    this.pickup,
    this.dropoff,
    this.pickupLabel,
    this.dropoffLabel,
    this.route = const [],
    this.secondaryRoute = const [],
    this.car,
    this.carHeading = 0,
    this.carGlide = true,
    this.etaText,
    this.etaAt,
    this.interactive = true,
    this.onTap,
    this.padding = const EdgeInsets.fromLTRB(40, 48, 40, 28),
    this.initialCenter = const LatLng(43.7102, 7.2620),
    this.initialZoom = 13,
    this.fitOnCreate = true,
    this.onCreated,
    this.onUserGesture,
  });

  List<LatLng> get framedPoints => [
        if (pickup != null) pickup!,
        if (dropoff != null) dropoff!,
        ...route,
        ...secondaryRoute,
        if (car != null) car!,
      ];

  @override
  State<VeyraGoogleMap> createState() => _VeyraGoogleMapState();
}

class _VeyraGoogleMapState extends State<VeyraGoogleMap> with SingleTickerProviderStateMixin {
  gm.GoogleMapController? _controller;
  VeyraIcon? _origin, _destination, _car, _eta;
  late final AnimationController _glide = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..addListener(_tick);
  LatLng? _carShown, _carFrom, _carTo;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _carShown = widget.car;
    _loadIcons();
  }

  @override
  void didUpdateWidget(covariant VeyraGoogleMap old) {
    super.didUpdateWidget(old);
    if (old.pickupLabel != widget.pickupLabel || old.dropoffLabel != widget.dropoffLabel || old.etaText != widget.etaText) _loadIcons();
    // A new trip (not a new car position) is framed again.
    final tripChanged = old.pickup != widget.pickup || old.dropoff != widget.dropoff || old.route.length != widget.route.length ||
        (widget.route.isNotEmpty && old.route.isNotEmpty && (old.route.first != widget.route.first || old.route.last != widget.route.last));
    if (tripChanged && widget.fitOnCreate) WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) fit(); });
    final next = widget.car;
    if (next == null) {
      _carShown = null;
    } else if (!widget.carGlide || _carShown == null) {
      _carShown = next;
    } else if (next != old.car) {
      _carFrom = _carShown;
      _carTo = next;
      _glide.forward(from: 0);
    }
  }

  void _tick() {
    final from = _carFrom, to = _carTo;
    if (from == null || to == null) return;
    final t = Curves.easeInOutCubic.transform(_glide.value);
    final now = DateTime.now();
    // Markers cross the platform channel: ~15 updates per second is fluid.
    if (_glide.value < 1 && now.difference(_lastFrame).inMilliseconds < 66) return;
    _lastFrame = now;
    if (!mounted) return;
    setState(() => _carShown = LatLng(from.latitude + (to.latitude - from.latitude) * t, from.longitude + (to.longitude - from.longitude) * t));
  }

  Future<void> _loadIcons() async {
    final results = await Future.wait([
      VeyraMarkerIcons.origin(widget.pickupLabel),
      VeyraMarkerIcons.destination(widget.dropoffLabel),
      VeyraMarkerIcons.car(),
      if (widget.etaText != null) VeyraMarkerIcons.eta(widget.etaText!),
    ]);
    if (!mounted) return;
    setState(() {
      _origin = results[0];
      _destination = results[1];
      _car = results[2];
      _eta = widget.etaText == null ? null : results[3];
    });
  }

  Future<void> fit() async {
    final c = _controller;
    final points = widget.framedPoints;
    if (c == null || points.isEmpty) return;
    try {
      await c.moveCamera(points.length == 1
          ? gm.CameraUpdate.newLatLngZoom(toGm(points.first), 15.5)
          : gm.CameraUpdate.newLatLngBounds(boundsOf(points), 24));
    } catch (_) {
      // The map is not laid out yet: retried on the next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) fit(); });
    }
  }

  @override
  void dispose() {
    _glide.dispose();
    super.dispose();
  }

  gm.Marker _marker(String id, LatLng p, VeyraIcon icon, {double rotation = 0, bool flat = false, int z = 0}) => gm.Marker(
        markerId: gm.MarkerId(id),
        position: toGm(p),
        icon: icon.icon,
        anchor: icon.anchor,
        rotation: rotation,
        flat: flat,
        zIndexInt: z,
        consumeTapEvents: true,
      );

  @override
  Widget build(BuildContext context) {
    final markers = <gm.Marker>{
      if (widget.pickup != null && _origin != null) _marker('pickup', widget.pickup!, _origin!, z: 2),
      if (widget.dropoff != null && _destination != null) _marker('dropoff', widget.dropoff!, _destination!, z: 2),
      if (widget.etaAt != null && _eta != null) _marker('eta', widget.etaAt!, _eta!, z: 3),
      if (_carShown != null && _car != null) _marker('car', _carShown!, _car!, rotation: widget.carHeading, flat: true, z: 4),
    };
    final polylines = <gm.Polyline>{
      if (widget.secondaryRoute.length >= 2) ...[
        gm.Polyline(polylineId: const gm.PolylineId('approach-casing'), points: widget.secondaryRoute.map(toGm).toList(), width: 9, color: Colors.white, zIndex: 0),
        gm.Polyline(polylineId: const gm.PolylineId('approach'), points: widget.secondaryRoute.map(toGm).toList(), width: 5, color: const Color(0xFF94A3B8), zIndex: 1),
      ],
      if (widget.route.length >= 2) ...[
        gm.Polyline(polylineId: const gm.PolylineId('route-casing'), points: widget.route.map(toGm).toList(), width: 9, color: Colors.white, zIndex: 2),
        gm.Polyline(polylineId: const gm.PolylineId('route'), points: widget.route.map(toGm).toList(), width: 5, color: VeyraMapMarks.routeBlue, zIndex: 3,
            jointType: gm.JointType.round, startCap: gm.Cap.roundCap, endCap: gm.Cap.roundCap),
      ],
    };
    final points = widget.framedPoints;
    final map = gm.GoogleMap(
      initialCameraPosition: gm.CameraPosition(target: toGm(points.isEmpty ? widget.initialCenter : points.first), zoom: widget.initialZoom),
      style: veyraMapStyle,
      padding: widget.padding,
      markers: markers,
      polylines: polylines,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      buildingsEnabled: false,
      indoorViewEnabled: false,
      trafficEnabled: false,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      scrollGesturesEnabled: widget.interactive,
      zoomGesturesEnabled: widget.interactive,
      // Inside a scrolling page the map keeps the finger when it is interactive.
      gestureRecognizers: widget.interactive ? {Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())} : const {},
      onTap: widget.onTap == null ? null : (p) => widget.onTap!(fromGm(p)),
      onMapCreated: (c) {
        _controller = c;
        widget.onCreated?.call(c);
        if (widget.fitOnCreate) WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) fit(); });
      },
    );
    if (widget.onUserGesture == null) return map;
    return Listener(onPointerDown: (_) => widget.onUserGesture!(), child: map);
  }
}
