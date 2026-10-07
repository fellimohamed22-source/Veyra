import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/core/widgets/booking_financial_summary.dart';

void main() {
  testWidgets('financial summary keeps server amounts and fits large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!),
        home: const Scaffold(
            body: BookingFinancialSummary(booking: {
          'driver_net_amount_minor': 10000,
          'platform_commission_amount_minor': 1500,
          'customer_total_amount_minor': 11500,
          'currency': 'EUR',
          'payment_method': 'ONLINE'
        }, paymentLabel: 'En cours de confirmation'))));
    expect(find.text('100,00 €'), findsOneWidget);
    expect(find.text('15,00 €'), findsOneWidget);
    expect(find.text('115,00 €'), findsOneWidget);
    expect(find.text('En cours de confirmation'), findsOneWidget);
    expect(find.text('Payé'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'missing breakdown is not fabricated and cash is not declared paid',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: BookingFinancialSummary(booking: {
      'customer_total_amount_minor': 11500,
      'payment_method': 'CASH'
    }, paymentLabel: 'Payé'))));
    expect(find.text('Prix chauffeur'), findsNothing);
    expect(find.text('Commission Veyra'), findsNothing);
    expect(find.text('Payé'), findsNothing);
    expect(
        find.text('Règlement en espèces auprès du chauffeur.'), findsOneWidget);
  });
}
