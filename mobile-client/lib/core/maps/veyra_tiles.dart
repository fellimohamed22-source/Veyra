import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../widgets/veyra_ui.dart' show veyraMapTilesEnabled;

/// Map background of the mock-ups (DEC-08: Google Maps).
///
/// With a mobile key passed at build time
/// (`--dart-define=GOOGLE_MAPS_MOBILE_KEY=…`, GitHub secret of the same
/// name), tiles come from the Google Map Tiles API — the exact roadmap look
/// of the boards, with the Google logo. Without a key, a light CARTO map
/// keeps the app usable until the key exists.
class VeyraTiles {
  VeyraTiles._();

  static const String _key = String.fromEnvironment('GOOGLE_MAPS_MOBILE_KEY');
  static bool get google => _key.isNotEmpty;

  static String? _session;
  static DateTime? _sessionExpiry;
  static Future<String?>? _pending;

  /// Google Map Tiles session (valid about two weeks, cached).
  static Future<String?> session() {
    if (!google) return Future.value(null);
    final s = _session;
    if (s != null && _sessionExpiry != null && DateTime.now().isBefore(_sessionExpiry!)) return Future.value(s);
    return _pending ??= _createSession().whenComplete(() => _pending = null);
  }

  static Future<String?> _createSession() async {
    try {
      final r = await Dio().post(
        'https://tile.googleapis.com/v1/createSession',
        queryParameters: {'key': _key},
        data: {'mapType': 'roadmap', 'language': 'fr-FR', 'region': 'FR', 'scale': 'scaleFactor2x', 'highDpi': true},
      );
      final data = Map<String, dynamic>.from(r.data as Map);
      _session = data['session']?.toString();
      final expiry = int.tryParse('${data['expiry'] ?? ''}');
      _sessionExpiry = expiry == null
          ? DateTime.now().add(const Duration(days: 1))
          : DateTime.fromMillisecondsSinceEpoch(expiry * 1000).subtract(const Duration(hours: 1));
      return _session;
    } catch (_) {
      return null;
    }
  }

  /// Base layer; nothing under `flutter test` (no network).
  static Widget layer(String package) {
    if (!veyraMapTilesEnabled) return const SizedBox.shrink();
    if (!google) return _carto(package);
    return FutureBuilder<String?>(
      future: session(),
      builder: (context, snap) {
        final s = snap.data;
        if (s == null) return snap.connectionState == ConnectionState.done ? _carto(package) : const SizedBox.shrink();
        return TileLayer(
          urlTemplate: 'https://tile.googleapis.com/v1/2dtiles/{z}/{x}/{y}?session=$s&key=$_key',
          userAgentPackageName: package,
          maxNativeZoom: 20,
        );
      },
    );
  }

  static Widget _carto(String package) => TileLayer(
        urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
        subdomains: const ['a', 'b', 'c', 'd'],
        retinaMode: true,
        userAgentPackageName: package,
      );

  /// Attribution required by the tile provider (Google logo bottom-left).
  static Widget attribution() => google
      ? const Positioned(
          left: 8,
          bottom: 6,
          child: IgnorePointer(
            child: Text('Google', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF5F6368), letterSpacing: -.2)),
          ),
        )
      : Positioned(
          right: 6,
          bottom: 4,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .85), borderRadius: BorderRadius.circular(4)),
              child: const Text('© OpenStreetMap © CARTO', style: TextStyle(fontSize: 8, color: Color(0xFF6B7280))),
            ),
          ),
        );
}
