import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/main.dart';
import 'package:veyra_client/core/widgets/veyra_ui.dart' show VeyraRouteMap;

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
        widget is TextField && widget.decoration?.hintText == 'Adresse de départ');
    await tester.enterText(pickup, 'Nice');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.enterText(pickup, 'Cannes');
    await tester.pump(const Duration(milliseconds: 450));
    expect(pending.keys, containsAll(['Nice', 'Cannes']));
    pending['Cannes']!('Cannes Centre, France');
    await tester.pumpAndSettle();
    pending['Nice']!('Nice Ville, France');
    await tester.pumpAndSettle();
    // Suggestions show the street as title and the rest as subtitle.
    expect(find.text('Cannes Centre'), findsOneWidget);
    expect(find.text('Nice Ville'), findsNothing);
    // Results sit right under the actions, the map is hidden while typing
    // (the keyboard would otherwise cover them).
    expect(find.byType(VeyraRouteMap), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
