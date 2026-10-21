import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/main.dart';

/// Board 01 P6: a request waiting for offers can be cancelled from its screen.
void main() {
  testWidgets('a request waiting for offers can be cancelled', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'accessToken': 't', 'refreshToken': 'r'});
    var cancelled = false;
    api.dio.interceptors.clear();
    addTearDown(api.dio.interceptors.clear);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      if (r.path.endsWith('/cancel')) {
        cancelled = true;
        return h.resolve(Response(requestOptions: r, statusCode: 200, data: {'status': 'CANCELLED_BY_CUSTOMER'}));
      }
      if (r.path.endsWith('/offers')) return h.resolve(Response(requestOptions: r, statusCode: 200, data: []));
      h.resolve(Response(requestOptions: r, statusCode: 200, data: {
        'id': 'b1', 'status': 'OPEN_FOR_OFFERS', 'pickup_address': 'Vieux-Port, Marseille', 'dropoff_address': 'Aéroport Marseille Provence',
        'scheduled_at': DateTime.now().add(const Duration(days: 1)).toUtc().toIso8601String(), 'passenger_count': 1, 'baggage_count': 1,
      }));
    }));
    await tester.pumpWidget(const MaterialApp(home: OffersScreen(bookingId: 'b1')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('cancel-request')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cancel-request')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Annuler la demande ?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Annuler la demande'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(cancelled, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
