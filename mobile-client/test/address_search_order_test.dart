import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/main.dart';

void main() {
  testWidgets('late address results cannot replace the current search',
      (tester) async {
    final pending = <String, void Function(String)>{};
    api.dio.interceptors.clear();
    addTearDown(api.dio.interceptors.clear);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      if (request.path.endsWith('/autocomplete')) {
        pending[request.queryParameters['q'] as String] = (label) =>
            handler.resolve(
                Response(requestOptions: request, statusCode: 200, data: [
              {'label': label, 'lat': 43.0, 'lng': 7.0}
            ]));
      } else {
        handler.resolve(Response(
            requestOptions: request, statusCode: 200, data: <dynamic>[]));
      }
    }));
    await tester.pumpWidget(const MaterialApp(home: AddressScreen()));
    await tester.pumpAndSettle();
    final pickup = find.byWidgetPredicate((widget) =>
        widget is TextField && widget.decoration?.labelText == 'Adresse de départ');
    await tester.enterText(pickup, 'Nice');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.enterText(pickup, 'Cannes');
    await tester.pump(const Duration(milliseconds: 450));
    expect(pending.keys, containsAll(['Nice', 'Cannes']));
    pending['Cannes']!('Cannes, France');
    await tester.pumpAndSettle();
    pending['Nice']!('Nice, France');
    await tester.pumpAndSettle();
    expect(find.text('Cannes, France'), findsOneWidget);
    expect(find.text('Nice, France'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
