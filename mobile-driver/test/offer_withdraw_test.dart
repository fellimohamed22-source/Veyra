import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/main.dart';
import 'package:veyra_driver/app/theme.dart';

void main() {
  testWidgets('withdraw cancellation and pending failure preserve a retryable offer',
      (tester) async {
    var deletes = 0;
    var withdrawn = false;
    RequestOptions? pendingRequest;
    RequestInterceptorHandler? pendingHandler;
    api.dio.interceptors.clear();
    addTearDown(api.dio.interceptors.clear);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      if (request.method == 'DELETE') {
        deletes++;
        pendingRequest = request;
        pendingHandler = handler;
        return;
      }
      handler.resolve(Response(requestOptions: request, statusCode: 200,
          data: request.queryParameters['scope'] == 'active' && !withdrawn
              ? [{'offer_id': 'offer-1', 'booking_id': 'ride-1',
                  'pickup_address': 'Nice', 'dropoff_address': 'Cannes',
                  'scheduled_at': '2026-10-12T12:00:00Z',
                  'status': 'ACTIVE', 'booking_status': 'OFFERS_RECEIVED',
                  'proposed_amount_minor': 2500}]
              : <dynamic>[]));
    }));
    await tester.pumpWidget(MaterialApp(theme: veyraTheme(),
        home: const MesOffresScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retirer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Garder mon offre'));
    await tester.pumpAndSettle();
    expect(deletes, 0);
    await tester.tap(find.text('Retirer'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Retirer'));
    await tester.pumpAndSettle();
    expect(deletes, 1);
    final button = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Retirer'));
    expect(button.onPressed, isNull);
    pendingHandler!.reject(DioException(requestOptions: pendingRequest!,
        type: DioExceptionType.connectionError));
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Retirer')).onPressed,
        isNotNull);
    expect(find.text('Nice → Cannes'), findsOneWidget);
    await tester.tap(find.text('Retirer'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Retirer'));
    await tester.pumpAndSettle();
    expect(deletes, 2);
    withdrawn = true;
    pendingHandler!.resolve(Response(requestOptions: pendingRequest!, statusCode: 204));
    await tester.pumpAndSettle();
    expect(find.text('Nice → Cannes'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
