import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/main.dart';

void main() {
  testWidgets('notification updates an open booking before its polling interval',
      (tester) async {
    var status = 'CONFIRMED';
    var verified = true;
    var reads = 0;
    api.dio.interceptors.clear();
    addTearDown(api.dio.interceptors.clear);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      reads++;
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'status': status,
        'selected_driver_id': 'driver-1',
        'driver_first_name': 'Alexandre',
        'driver_verified': verified,
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
    await tester.scrollUntilVisible(find.text('Chauffeur Veyra vérifié'), 180);
    expect(find.text('Chauffeur Veyra vérifié'), findsOneWidget);
    status = 'DRIVER_ARRIVED';
    verified = false;
    RefreshBus.bump();
    await tester.pumpAndSettle();
    expect(reads, initialReads + 1);
    await tester.scrollUntilVisible(find.text('Votre chauffeur est arrivé'), 180);
    expect(find.text('Votre chauffeur est arrivé'), findsOneWidget);
    expect(find.text('Chauffeur Veyra vérifié'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    RefreshBus.bump();
    await tester.pumpAndSettle();
    expect(reads, initialReads + 1);
  });
}
