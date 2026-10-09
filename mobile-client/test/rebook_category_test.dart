import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/main.dart';

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
      await tester.scrollUntilVisible(find.text('Publier la demande'), 400,
          scrollable: find.byType(Scrollable).first);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Publier la demande'));
      await tester.pumpAndSettle();
      expect(posted, isFalse);
      expect(
          find.text(retired
              ? 'Complétez le trajet, la date et la catégorie.'
              : 'Le nombre de passagers dépasse la capacité de cette catégorie.'),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
