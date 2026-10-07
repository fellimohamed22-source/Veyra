import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/main.dart';

void main() {
  testWidgets('an empty offer list still reports refresh failure and recovery',
      (tester) async {
    var offline = false;
    api.dio.interceptors.clear();
    addTearDown(api.dio.interceptors.clear);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      if (offline) {
        handler.reject(DioException(
            requestOptions: request, type: DioExceptionType.connectionError));
        return;
      }
      handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: request.path.endsWith('/offers')
              ? <dynamic>[]
              : <String, dynamic>{}));
    }));
    await tester
        .pumpWidget(const MaterialApp(home: OffersScreen(bookingId: 'ride-1')));
    await tester.pumpAndSettle();
    offline = true;
    await tester.tap(find.byTooltip('Actualiser'));
    await tester.pumpAndSettle();
    expect(find.text('Actualisation interrompue. Vérifiez votre connexion.'),
        findsOneWidget);
    offline = false;
    await tester.tap(find.byTooltip('Actualiser'));
    await tester.pumpAndSettle();
    expect(find.text('Actualisation interrompue. Vérifiez votre connexion.'),
        findsNothing);
    expect(find.byType(RefreshIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
