import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/main.dart';
import 'package:veyra_driver/core/widgets/state_views.dart';

void main() {
  testWidgets('recovering a request also loads route economics',
      (tester) async {
    var offline = true;
    var routes = 0;
    api.dio.interceptors.clear();
    addTearDown(api.dio.interceptors.clear);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      if (offline) {
        handler.reject(DioException(
            requestOptions: request, type: DioExceptionType.connectionError));
        return;
      }
      if (request.path.endsWith('/estimate')) routes++;
      handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: request.path.endsWith('/estimate')
              ? {'distanceMeters': 12000, 'durationSeconds': 1200}
              : {
                  'pickup_address': 'Nice',
                  'dropoff_address': 'Cannes',
                  'pickup_lat': 43.7,
                  'pickup_lng': 7.2,
                  'dropoff_lat': 43.5,
                  'dropoff_lng': 7.0,
                  'scheduled_at': '2026-10-12T12:00:00Z',
                  'category_name': 'Standard',
                  'passenger_count': 2,
                  'baggage_count': 1
                }));
    }));
    await tester.pumpWidget(
        const MaterialApp(home: RequestScreen(bookingId: 'ride-1')));
    await tester.pumpAndSettle();
    expect(find.byType(VeyraOfflineBanner), findsOneWidget);
    expect(find.text('Elle a peut-être déjà été fermée.'), findsNothing);
    offline = false;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(routes, 1);
    // Board 12 P3: « ≈ 12,0 km · 20 min » in the trip-type pill.
    expect(find.text('≈ 12,0 km · 20 min'), findsOneWidget);
    expect(find.byType(VeyraOfflineBanner), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
