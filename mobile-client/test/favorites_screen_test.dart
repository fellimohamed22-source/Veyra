import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/main.dart';
import 'package:veyra_client/app/theme.dart';

void main() {
  tearDown(api.dio.interceptors.clear);
  testWidgets('favorite driver actions fit the actual theme on a narrow screen',
      (tester) async {
    api.dio.interceptors.clear();
    api.dio.interceptors.add(InterceptorsWrapper(
        onRequest: (request, handler) => handler.resolve(
                Response(requestOptions: request, statusCode: 200, data: [
              {
                'driver_id': 'driver-1',
                'booking_id': 'ride-1',
                'first_name': 'Alexandre',
                'last_name': 'Martin',
                'rating': 4.8,
                'brand': 'Mercedes',
                'model': 'Classe E',
                'color': 'Noir',
                'category_name': 'Confort'
              }
            ]))));
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: veyraTheme(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!),
        home: const FavoriteDriversScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Alexandre Martin'), findsOneWidget);
    expect(find.text('Réserver à nouveau'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'editing a saved address ignores search results for previous text',
      (tester) async {
    RequestInterceptorHandler? pending;
    RequestOptions? pendingOptions;
    api.dio.interceptors.clear();
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      if (request.path.endsWith('/autocomplete')) {
        pending = handler;
        pendingOptions = request;
        return;
      }
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: [
        {
          'id': 'saved-1',
          'label': 'Maison',
          'address': 'Nice',
          'lat': 43.7,
          'lng': 7.2
        }
      ]));
    }));
    await tester.pumpWidget(const MaterialApp(home: SavedAddressesScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modifier'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Nice');
    await tester.tap(find.text('Rechercher'));
    await tester.pumpAndSettle();
    expect(pending, isNotNull);
    await tester.enterText(find.byType(TextField).last, 'Paris');
    pending!.resolve(
        Response(requestOptions: pendingOptions!, statusCode: 200, data: [
      {'label': 'Ancienne suggestion Nice', 'lat': 43.7, 'lng': 7.2}
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Ancienne suggestion Nice'), findsNothing);
    final save = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Enregistrer'));
    expect(save.onPressed, isNull);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'saved address edit validates before closing; deletion requires confirmation',
      (tester) async {
    var puts = 0, deletes = 0;
    final address = <String, dynamic>{
      'id': 'saved-1',
      'label': 'Maison',
      'address': 'Nice',
      'lat': 43.7,
      'lng': 7.2
    };
    api.dio.interceptors.clear();
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      if (request.method == 'PUT') {
        puts++;
        address.addAll(Map<String, dynamic>.from(request.data as Map));
      }
      if (request.method == 'DELETE') deletes++;
      handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: deletes > 0 ? <dynamic>[] : [address]));
    }));
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: veyraTheme(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!),
        home: const SavedAddressesScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modifier'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('Nom de l’adresse requis.'), findsOneWidget);
    expect(puts, 0);
    await tester.enterText(find.byType(TextFormField), 'Travail');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(puts, 1);
    expect(find.text('Travail'), findsOneWidget);
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    expect(deletes, 0);
    await tester.tap(find.text('Conserver'));
    await tester.pumpAndSettle();
    expect(deletes, 0);
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Supprimer')));
    await tester.pumpAndSettle();
    expect(deletes, 1);
    expect(find.text('Travail'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
