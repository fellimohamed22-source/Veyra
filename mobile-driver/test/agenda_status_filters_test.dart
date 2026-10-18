import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/main.dart';

/// Board 12 P6: « À venir » (nearest first) and « Historique » (latest first).
void main() {
  testWidgets('agenda tabs ask the server for upcoming then history rides', (tester) async {
    final requests = <Map<String, dynamic>>[];
    api.dio.interceptors.clear();
    addTearDown(api.dio.interceptors.clear);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(Map.from(request.queryParameters));
      final history = request.queryParameters['scope'] == 'history';
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: [
        {
          'id': history ? 'past-1' : 'next-1',
          'status': history ? 'COMPLETED' : 'CONFIRMED',
          'scheduled_at': DateTime.now().add(Duration(days: history ? -2 : 1)).toUtc().toIso8601String(),
          'pickup_address': history ? 'Neuilly' : 'Paris',
          'dropoff_address': history ? 'Versailles' : 'Orly',
          'passenger_count': 2,
          'baggage_count': 1,
          'driver_net_amount_minor': 4500,
        },
      ]));
    }));
    await tester.pumpWidget(const MaterialApp(home: AgendaScreen()));
    await tester.pumpAndSettle();
    expect(requests.last, {'scope': 'upcoming', 'page': 0, 'sort': 'asc'});
    expect(find.text('Confirmée'), findsOneWidget);
    expect(find.text('Voir les détails'), findsOneWidget);

    await tester.tap(find.text('Historique'));
    await tester.pumpAndSettle();
    expect(requests.last, {'scope': 'history', 'page': 0, 'sort': 'desc'});
    expect(find.text('Terminée'), findsOneWidget);
    expect(find.text('45,00 €'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
