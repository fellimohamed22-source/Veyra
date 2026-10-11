import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/main.dart';

void main() {
  testWidgets('every agenda status is sent exactly to the server',
      (tester) async {
    final requests = <Map<String, dynamic>>[];
    api.dio.interceptors.clear();
    addTearDown(api.dio.interceptors.clear);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(Map.from(request.queryParameters));
      handler.resolve(Response(
          requestOptions: request, statusCode: 200, data: <dynamic>[]));
    }));
    await tester.pumpWidget(const MaterialApp(home: AgendaScreen()));
    await tester.pumpAndSettle();
    var selected = 'ALL';
    for (final status in [
      'CONFIRMED',
      'DRIVER_EN_ROUTE',
      'DRIVER_ARRIVED',
      'IN_PROGRESS',
      'COMPLETED',
      'CLOSED',
      'CANCELLED',
      'DRIVER_CANCELLED',
      'CUSTOMER_NO_SHOW'
    ]) {
      final filter = tester.widget<DropdownButtonFormField<String>>(
          find.byKey(ValueKey('booking-status-$selected')));
      final dropdown = tester.widget<DropdownButton<String>>(find.descendant(
          of: find.byKey(ValueKey('booking-status-$selected')),
          matching: find.byType(DropdownButton<String>)));
      expect(dropdown.items!.any((item) => item.value == status), isTrue);
      filter.onChanged!(status);
      await tester.pumpAndSettle();
      expect(requests.last,
          {'scope': 'all', 'status': status, 'sort': 'asc', 'page': 0});
      selected = status;
    }
    tester
        .widget<DropdownButtonFormField<String>>(
            find.byKey(const ValueKey('booking-sort-asc')))
        .onChanged!('desc');
    await tester.pumpAndSettle();
    expect(requests.last, {
      'scope': 'all',
      'status': 'CUSTOMER_NO_SHOW',
      'sort': 'desc',
      'page': 0
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
