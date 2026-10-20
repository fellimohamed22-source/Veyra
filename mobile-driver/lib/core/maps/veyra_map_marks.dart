import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Marks drawn on the maps of the boards (03, 04, 10 P4, 12 P3/P8):
/// blue ring at the start, red pin at the destination, each with its place
/// name, the car seen from above, the blue duration bubble on the route.
class VeyraMapMarks {
  VeyraMapMarks._();

  static const routeBlue = Color(0xFF2F6FE4);
  static const pinRed = Color(0xFFE53935);

  /// Route as on the boards: blue line with a thin white casing.
  static Widget route(List<LatLng> points) => PolylineLayer(polylines: [
        Polyline(points: points, strokeWidth: 8, color: Colors.white.withValues(alpha: .95)),
        Polyline(points: points, strokeWidth: 5, color: routeBlue),
      ]);

  static const double _labelBox = 240;

  static Marker origin(LatLng p, {String? label}) => Marker(
        point: p,
        width: _labelBox,
        height: 40,
        child: Stack(clipBehavior: Clip.none, children: [
          Center(
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: routeBlue, width: 5),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 5, offset: Offset(0, 2))],
              ),
            ),
          ),
          if (label != null && label.isNotEmpty) Positioned(left: _labelBox / 2 + 14, top: 6, child: placeLabel(label)),
        ]),
      );

  static Marker destination(LatLng p, {String? label}) => Marker(
        point: p,
        width: _labelBox,
        height: 46,
        alignment: Alignment.topCenter,
        child: Stack(clipBehavior: Clip.none, children: [
          const Align(alignment: Alignment.bottomCenter, child: Icon(Icons.location_on, color: pinRed, size: 40)),
          if (label != null && label.isNotEmpty) Positioned(left: _labelBox / 2 + 16, top: 0, right: 0, child: placeLabel(label, maxLines: 3)),
        ]),
      );

  /// Car seen from above, rotated by the GPS heading (0° = north).
  static Marker car(LatLng p, {double heading = 0}) => Marker(
        point: p,
        width: 46,
        height: 46,
        child: Transform.rotate(angle: heading * math.pi / 180, child: const CustomPaint(painter: VeyraCarPainter())),
      );

  /// Duration bubble on the route (« 8 min », board 10 P4).
  static Marker eta(LatLng p, String text) => Marker(
        point: p,
        width: 120,
        height: 34,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: routeBlue,
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
            ),
            child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ),
      );

  /// Place name with a white halo, readable over the map.
  static Widget placeLabel(String text, {int maxLines = 2}) {
    const style = TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.15);
    return Stack(children: [
      Text(text, maxLines: maxLines, overflow: TextOverflow.ellipsis,
          style: style.copyWith(foreground: Paint()..style = PaintingStyle.stroke..strokeWidth = 4..color = Colors.white)),
      Text(text, maxLines: maxLines, overflow: TextOverflow.ellipsis, style: style.copyWith(color: const Color(0xFF0E1A2B))),
    ]);
  }

  /// Point halfway along the polyline (by distance), for the duration bubble.
  static LatLng? midpoint(List<LatLng> points) {
    if (points.length < 2) return points.isEmpty ? null : points.first;
    const d = Distance();
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += d(points[i - 1], points[i]);
    }
    var walked = 0.0;
    for (var i = 1; i < points.length; i++) {
      final seg = d(points[i - 1], points[i]);
      if (walked + seg >= total / 2 && seg > 0) {
        final t = (total / 2 - walked) / seg;
        return LatLng(points[i - 1].latitude + (points[i].latitude - points[i - 1].latitude) * t,
            points[i - 1].longitude + (points[i].longitude - points[i - 1].longitude) * t);
      }
      walked += seg;
    }
    return points.last;
  }
}

/// Round white map button (recenter « ⌖ » of the boards).
class VeyraMapButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  const VeyraMapButton({required this.icon, required this.tooltip, this.onPressed, super.key});
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        elevation: 3,
        shadowColor: Colors.black26,
        shape: const CircleBorder(),
        child: IconButton(tooltip: tooltip, onPressed: onPressed, icon: Icon(icon, color: const Color(0xFF0E1A2B), size: 24)),
      );
}

/// Dark saloon seen from above (north-facing; the marker rotates it).
class VeyraCarPainter extends CustomPainter {
  const VeyraCarPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final shadow = Paint()..color = Colors.black26..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final body = Paint()..color = const Color(0xFF1F2933);
    final roof = Paint()..color = const Color(0xFF111827);
    final glass = Paint()..color = const Color(0xFF8FB8DE);
    final light = Paint()..color = const Color(0xFFFFF7D6);
    final car = RRect.fromRectAndRadius(Rect.fromLTWH(w * .28, h * .04, w * .44, h * .92), Radius.circular(w * .16));
    canvas.drawRRect(car.shift(const Offset(1, 2)), shadow);
    canvas.drawRRect(car, body);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * .33, h * .40, w * .34, h * .26), Radius.circular(w * .06)), roof);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * .33, h * .22, w * .34, h * .16), Radius.circular(w * .06)), glass);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * .34, h * .68, w * .32, h * .12), Radius.circular(w * .05)), glass);
    canvas.drawCircle(Offset(w * .36, h * .08), w * .035, light);
    canvas.drawCircle(Offset(w * .64, h * .08), w * .035, light);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
