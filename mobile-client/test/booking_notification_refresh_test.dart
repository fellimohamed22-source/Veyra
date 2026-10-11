import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/main.dart';

void main() {
  testWidgets('notification updates an open booking before its polling interval',
      (tester) async {
    var status = 'CONFIRMED';
    var reads = 0;
    api.dio.interceptors.clear();
    addTearDown(api.dio.interceptors.clear);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      reads++;
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'status': status,
        'payment_method': 'CASH',
        'pickup_address': 'Nice',
        'dropoff_address': 'Cannes',
        'scheduled_at': '2026-10-11T15:00:00Z',
      }));
    }));
    await tester.pumpWidget(const MaterialApp(
        home: BookingDetailScreen(bookingId: 'ride-1')));
    await tester.pumpAndSettle();
    final initialReads = reads;
    expect(find.text('Votre chauffeur est arrivé'), findsNothing);
    status = 'DRIVER_ARRIVED';
    RefreshBus.bump();
    await tester.pumpAndSettle();
    expect(reads, initialReads + 1);
    expect(find.text('Votre chauffeur est arrivé'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    RefreshBus.bump();
    await tester.pumpAndSettle();
    expect(reads, initialReads + 1);
  });
}
