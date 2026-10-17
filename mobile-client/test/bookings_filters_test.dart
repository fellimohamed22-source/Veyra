import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/main.dart';

String _at(int hours) => DateTime.now().add(Duration(hours: hours)).toUtc().toIso8601String();

void main() {
  tearDown(api.dio.interceptors.clear);

  void serve(List<Map<String, dynamic>> rows, List<RequestOptions> seen) {
    api.dio.interceptors.clear();
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      seen.add(request);
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: rows));
    }));
  }

  final rows = [
    {'id': 'wait', 'status': 'OPEN_FOR_OFFERS', 'pickup_address': 'Lyon', 'dropoff_address': 'Saint-Exupéry', 'scheduled_at': _at(30), 'offer_count': 0},
    {'id': 'offers', 'status': 'OFFERS_RECEIVED', 'pickup_address': 'Paris', 'dropoff_address': 'CDG', 'scheduled_at': _at(20), 'offer_count': 3, 'best_offer_total_minor': 5280},
    {'id': 'confirmed', 'status': 'CONFIRMED', 'pickup_address': 'Nice', 'dropoff_address': 'Cannes', 'scheduled_at': _at(40), 'selected_driver_id': 'd', 'driver_name': 'Thomas Martin'},
    {'id': 'done', 'status': 'COMPLETED', 'pickup_address': 'Nantes', 'dropoff_address': 'Rennes', 'scheduled_at': _at(-40)},
    {'id': 'cancel', 'status': 'DRIVER_CANCELLED', 'pickup_address': 'Lille', 'dropoff_address': 'Arras', 'scheduled_at': _at(10)},
  ];

  testWidgets('requests are split into the board 05 tabs with their counts', (tester) async {
    final seen = <RequestOptions>[];
    serve(rows, seen);
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();
    // Whole list fetched once, unpaginated, then filtered per tab.
    expect(seen.single.queryParameters.containsKey('page'), isFalse);
    expect(find.text('En attente (1)'), findsOneWidget);
    expect(find.text('Offres reçues (1)'), findsOneWidget);
    expect(find.text('Confirmées (1)'), findsOneWidget);
    expect(find.text('Lyon'), findsOneWidget);
    expect(find.text('Paris'), findsNothing);

    await tester.tap(find.text('Offres reçues (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Paris'), findsOneWidget);
    expect(find.text('3 offres reçues'), findsOneWidget);
    expect(find.text('Meilleur prix disponible'), findsOneWidget);
    expect(find.text('52,80 €'), findsOneWidget);
    expect(find.text('Voir les offres'), findsOneWidget);

    await tester.tap(find.text('Confirmées (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Thomas Martin'), findsOneWidget);
    expect(find.text('Voir ma réservation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reservations separate upcoming, past and cancelled rides', (tester) async {
    serve(rows, []);
    await tester.pumpWidget(const MaterialApp(home: ReservationsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('À venir (1)'), findsOneWidget);
    expect(find.text('Passées (1)'), findsOneWidget);
    expect(find.text('Annulées (1)'), findsOneWidget);
    await tester.tap(find.text('Annulées (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Lille'), findsOneWidget);
    expect(find.text('Annulée'), findsOneWidget);
    await tester.tap(find.text('Passées (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Nantes'), findsOneWidget);
    expect(find.text('Terminée'), findsOneWidget);
  });

  testWidgets('an empty tab says so instead of showing a blank list', (tester) async {
    serve([rows.first], []);
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmées (0)'));
    await tester.pumpAndSettle();
    expect(find.text('Aucune demande dans cette catégorie.'), findsOneWidget);
  });
}
