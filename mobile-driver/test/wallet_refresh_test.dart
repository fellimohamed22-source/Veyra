import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:veyra_driver/main.dart';
import 'package:veyra_driver/app/theme.dart';

void main() {
  testWidgets('wallet opens the linked ride and leaves unlinked payouts inert',
      (tester) async {
    api.dio.interceptors.clear();
    addTearDown(api.dio.interceptors.clear);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      handler.resolve(Response(
        requestOptions: request,
        statusCode: 200,
        data: request.path.endsWith('transactions')
            ? [
                {
                  'event_type': 'DRIVER_PAYABLE_PAID',
                  'amount_minor': 3400,
                  'created_at': '2026-10-11T10:00:00Z',
                },
                {
                  'event_type': 'BOOKING_COMPLETED_ONLINE',
                  'amount_minor': 1200,
                  'booking_id': 'ride-wallet-1',
                  'created_at': '2026-10-11T09:00:00Z',
                },
              ]
            : {'onlinePayableMinor': 1200, 'cashDebtMinor': 0},
      ));
    }));
    final navigation = GoRouter(initialLocation: '/wallet', routes: [
      GoRoute(path: '/wallet', builder: (_, __) => const WalletScreen()),
      GoRoute(
          path: '/ride/:id',
          builder: (_, state) =>
              Scaffold(body: Text('Course ${state.pathParameters['id']}'))),
    ]);
    addTearDown(navigation.dispose);
    await tester.pumpWidget(
        MaterialApp.router(theme: veyraTheme(), routerConfig: navigation));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Versement reçu'), 150,
        scrollable: find.byType(Scrollable).first);
    final payout = find.ancestor(
        of: find.text('Versement reçu'), matching: find.byType(ListTile));
    expect(tester.widget<ListTile>(payout).onTap, isNull);
    await tester.tap(find.text('Versement reçu'));
    await tester.pumpAndSettle();
    expect(navigation.routeInformationProvider.value.uri.path, '/wallet');
    await tester.scrollUntilVisible(
        find.text('Course terminée (paiement en ligne)'), 100,
        scrollable: find.byType(Scrollable).first);
    final linkedRide = find.ancestor(
        of: find.text('Course terminée (paiement en ligne)'),
        matching: find.byType(ListTile));
    final rideTile = tester.widget<ListTile>(linkedRide);
    expect(rideTile.onTap, isNotNull,
        reason: 'A wallet transaction linked to a ride must be actionable');
    // GoRouter.push adds an imperative route on top of /wallet. Its
    // routeInformationProvider can keep the base location (/wallet), so
    // asserting that provider's URI incorrectly reports a navigation failure.
    // Verify the destination is actually rendered and can be popped instead.
    rideTile.onTap!();
    await tester.pumpAndSettle();
    expect(find.text('Course ride-wallet-1'), findsOneWidget);
    expect(navigation.canPop(), isTrue);
    navigation.pop();
    await tester.pumpAndSettle();
    expect(find.text('Versement reçu'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

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
