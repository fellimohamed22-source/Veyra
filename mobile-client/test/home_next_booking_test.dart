import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/main.dart';

void main() {
  tearDown(api.dio.interceptors.clear);
  for (final onlyCancelled in [false, true]) {
    testWidgets(
        'driver cancellation is excluded from next booking ($onlyCancelled)',
        (tester) async {
      api.dio.interceptors.clear();
      api.dio.interceptors.add(InterceptorsWrapper(
          onRequest: (request, handler) => handler.resolve(Response(
              requestOptions: request,
              statusCode: 200,
              data: request.path.endsWith('/me')
                  ? <String, dynamic>{}
                  : <dynamic>[
                      {
                        'id': 'cancelled',
                        'status': 'DRIVER_CANCELLED',
                        'pickup_address': 'Ancien départ',
                        'dropoff_address': 'Ancienne destination',
                        'scheduled_at': DateTime.now()
                            .add(const Duration(hours: 3))
                            .toIso8601String()
                      },
                      if (!onlyCancelled)
                        {
                          'id': 'next',
                          'status': 'CONFIRMED',
                          'pickup_address': 'Nouveau départ',
                          'dropoff_address': 'Nouvelle destination',
                          'scheduled_at': DateTime.now()
                              .add(const Duration(hours: 5))
                              .toIso8601String()
                        },
                    ]))));
      await tester.pumpWidget(const MaterialApp(home: AccueilScreen()));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ancien départ'), findsNothing);
      if (onlyCancelled) {
        expect(
            find.text(
                'Aucune réservation à venir. Votre prochain trajet apparaîtra ici.'),
            findsOneWidget);
      } else {
        expect(
            find.text('Nouveau départ → Nouvelle destination'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
