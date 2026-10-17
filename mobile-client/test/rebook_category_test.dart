import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/main.dart';

Finder _next() => find.widgetWithText(FilledButton, 'Suivant');

Future<void> _tapNext(WidgetTester tester) async {
  await tester.tap(_next());
  await tester.pumpAndSettle();
}

void main() {
  for (final retired in [false, true]) {
    testWidgets(
        retired
            ? 'rebook requires a new category when the old one is retired'
            : 'rebook reloads capacity without silently reducing passengers',
        (tester) async {
      var posted = false;
      api.dio.interceptors.clear();
      addTearDown(api.dio.interceptors.clear);
      api.dio.interceptors
          .add(InterceptorsWrapper(onRequest: (request, handler) {
        if (request.method == 'POST') posted = true;
        handler
            .resolve(Response(requestOptions: request, statusCode: 200, data: [
          {
            'id': retired ? 'replacement' : 'old',
            'display_name': 'Berline',
            'capacity': 3
          }
        ]));
      }));
      await tester.pumpWidget(const MaterialApp(
          home: AddressScreen(initialBooking: {
        'category_id': 'old',
        'passenger_count': 4,
        'customer_notes': 'Siège enfant',
        'pickup_address': 'Nice',
        'pickup_lat': 43.7,
        'pickup_lng': 7.2,
        'dropoff_address': 'Cannes',
        'dropoff_lat': 43.5,
        'dropoff_lng': 7.0
      })));
      await tester.pumpAndSettle();
      await _tapNext(tester); // départ -> destination
      await _tapNext(tester); // destination -> véhicule
      expect(tester.takeException(), isNull);
      if (retired) {
        // The retired category is no longer selected: a new choice is required.
        expect(tester.widget<FilledButton>(_next()).onPressed, isNull);
      } else {
        await _tapNext(tester); // véhicule -> détails
        expect(find.text('Le nombre de passagers dépasse la capacité du véhicule sélectionné.'), findsOneWidget);
        expect(find.text('4'), findsOneWidget, reason: 'passengers must not be silently reduced');
        expect(tester.widget<FilledButton>(_next()).onPressed, isNull);
      }
      expect(posted, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
