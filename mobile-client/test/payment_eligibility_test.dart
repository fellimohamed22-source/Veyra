import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/main.dart';

void main() {
  test('payment actions follow the server booking states and payment method',
      () {
    for (final status in ['CONFIRMED', 'DRIVER_EN_ROUTE', 'DRIVER_ARRIVED']) {
      expect(
          bookingCanPayOnline({'status': status, 'payment_method': 'ONLINE'}),
          isTrue);
      expect(bookingCanPayOnline({'status': status, 'payment_method': 'CASH'}),
          isFalse);
      expect(
          bookingCanPayOnline({
            'status': status,
            'payment_method': 'ONLINE',
            'payment_status': 'CAPTURED'
          }),
          isFalse);
    }
    for (final status in [
      'OPEN_FOR_OFFERS',
      'OFFERS_RECEIVED',
      'IN_PROGRESS',
      'COMPLETED',
      'CLOSED',
      'CANCELLED',
      'DRIVER_CANCELLED',
      'CUSTOMER_NO_SHOW'
    ]) {
      expect(
          bookingCanPayOnline({'status': status, 'payment_method': 'ONLINE'}),
          isFalse);
    }
    expect(bookingCanPayOnline(null), isFalse);
  });
  testWidgets(
      'an old payment link cannot offer payment for a cancelled booking',
      (tester) async {
    api.dio.interceptors.clear();
    addTearDown(api.dio.interceptors.clear);
    api.dio.interceptors.add(InterceptorsWrapper(
        onRequest: (request, handler) => handler.resolve(
                Response(requestOptions: request, statusCode: 200, data: {
              'status': 'CANCELLED',
              'payment_method': 'ONLINE',
              'customer_total_amount_minor': 5000
            }))));
    await tester.pumpWidget(
        const MaterialApp(home: PaymentScreen(bookingId: 'cancelled-ride')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Payer maintenant'))
            .onPressed,
        isNull);
    expect(
        find.text(
            'Cette réservation ne nécessite pas de paiement en ligne à cette étape.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
