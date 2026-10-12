import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:veyra_client/core/widgets/booking_route_preview.dart';

void main() {
  setUp(() => BookingRoutePreview.enableNetworkTiles = false);
  tearDown(() => BookingRoutePreview.enableNetworkTiles = true);

  testWidgets('route preview displays indicative distance and duration',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: BookingRoutePreview(
        pickupLat: 43.7, pickupLng: 7.2,
        dropoffLat: 43.5, dropoffLng: 7.0,
        distanceMeters: 12500, durationSeconds: 1860,
        routePoints: [LatLng(43.7, 7.2), LatLng(43.5, 7.0)],
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('12.5 km • environ 31 min'), findsOneWidget);
    expect(find.textContaining('Le prix sera proposé'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('route preview error allows retry without blocking booking',
      (tester) async {
    var retries = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BookingRoutePreview(
        pickupLat: 43.7, pickupLng: 7.2,
        dropoffLat: 43.5, dropoffLng: 7.0,
        error: 'Estimation indisponible',
        onRetry: () => retries++,
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Estimation indisponible'), findsOneWidget);
    await tester.tap(find.text('Réessayer'));
    expect(retries, 1);
    expect(tester.takeException(), isNull);
  });
}
