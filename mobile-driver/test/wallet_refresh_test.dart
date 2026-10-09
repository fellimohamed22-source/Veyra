import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/main.dart';

void main() {
  testWidgets('wallet refresh updates both balance and transaction history',
      (tester) async {
    var balanceRequests = 0;
    var historyRequests = 0;
    api.dio.interceptors.clear();
    addTearDown(api.dio.interceptors.clear);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      final history = request.path.endsWith('transactions');
      if (history) {
        historyRequests++;
      } else {
        balanceRequests++;
      }
      handler.resolve(Response(
        requestOptions: request,
        statusCode: 200,
        data: history
            ? <dynamic>[]
            : {
                'onlinePayableMinor': balanceRequests == 1 ? 1200 : 3400,
                'cashDebtMinor': 0,
              },
      ));
    }));
    await tester.pumpWidget(const MaterialApp(home: WalletScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Solde à recevoir'), findsOneWidget);
    expect(find.text('12,00 €'), findsOneWidget);
    expect(balanceRequests, 1);
    expect(historyRequests, 1);

    await tester.tap(find.byTooltip('Actualiser'));
    await tester.pumpAndSettle();
    expect(find.text('34,00 €'), findsOneWidget);
    expect(find.text('12,00 €'), findsNothing);
    expect(balanceRequests, 2);
    expect(historyRequests, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
