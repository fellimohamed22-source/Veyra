import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/main.dart';

void main() {
  testWidgets('reused opportunity ignores late route from the previous booking',
      (tester) async {
    final oldRoute = Completer<void>();
    api.dio.interceptors.clear();
    addTearDown(api.dio.interceptors.clear);
    var requests = 0;
    api.dio.interceptors
        .add(InterceptorsWrapper(onRequest: (request, handler) async {
      final requestNumber = ++requests;
      if (requestNumber == 1) await oldRoute.future;
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'distanceMeters': requestNumber == 1 ? 12000 : 24000,
        'durationSeconds': 1200
      }));
    }));
    Widget screen(double lat) => MaterialApp(
            home: Scaffold(
                body: OpportunityDistanceSummary(booking: {
          'pickup_lat': lat,
          'pickup_lng': 6,
          'dropoff_lat': 44,
          'dropoff_lng': 7,
        }, position: Future.value(null))));
    await tester.pumpWidget(screen(43));
    await tester.pumpAndSettle();
    expect(requests, 1);
    await tester.pumpWidget(screen(42));
    await tester.pumpAndSettle();
    expect(find.text('Course : 24,0 km • 20 min'), findsOneWidget);
    oldRoute.complete();
    await tester.pumpAndSettle();
    expect(find.text('Course : 24,0 km • 20 min'), findsOneWidget);
    expect(find.textContaining('12,0 km'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
