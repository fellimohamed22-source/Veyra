import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/main.dart';

void main() {
  tearDown(api.dio.interceptors.clear);
  testWidgets('booking status and date order reach the server and reset page',
      (tester) async {
    final requests = <Map<String, dynamic>>[];
    api.dio.interceptors.clear();
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(Map.from(request.queryParameters));
      handler.resolve(Response(
          requestOptions: request, statusCode: 200, data: <dynamic>[]));
    }));
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();
    expect(requests.last, {'sort': 'desc', 'page': 0});
    tester
        .widget<DropdownButtonFormField<String>>(
            find.byKey(const ValueKey('ALL')))
        .onChanged!('COMPLETED');
    await tester.pumpAndSettle();
    expect(requests.last, {'status': 'COMPLETED', 'sort': 'desc', 'page': 0});
    expect(find.text('Aucune réservation ne correspond aux filtres.'),
        findsOneWidget);
    tester
        .widget<DropdownButtonFormField<String>>(
            find.byKey(const ValueKey('desc')))
        .onChanged!('asc');
    await tester.pumpAndSettle();
    expect(requests.last, {'status': 'COMPLETED', 'sort': 'asc', 'page': 0});
    await tester.tap(find.text('Réinitialiser'));
    await tester.pumpAndSettle();
    expect(requests.last, {'sort': 'desc', 'page': 0});
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('empty last booking page retains a way back to the previous page',
      (tester) async {
    final pages = <int>[];
    api.dio.interceptors.clear();
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      final page = request.queryParameters['page'] as int;
      pages.add(page);
      handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: page > 0
              ? <dynamic>[]
              : List.generate(
                  10,
                  (i) => {
                        'id': 'ride-$i',
                        'status': 'CONFIRMED',
                        'pickup_address': 'Départ $i',
                        'dropoff_address': 'Destination $i',
                        'scheduled_at': '2026-10-11T12:00:00Z',
                        'payment_method': 'CASH',
                        'passenger_count': 1,
                        'baggage_count': 0,
                      })));
    }));
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Suivant'), 300);
    await tester.ensureVisible(find.text('Suivant'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    expect(pages.last, 1);
    await tester.ensureVisible(find.text('Page précédente'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Page précédente'));
    await tester.pumpAndSettle();
    expect(pages, [0, 1, 0]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
