import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:veyra_driver/main.dart';
import 'package:veyra_driver/app/theme.dart';

void main() {
  for (final adjusting in [false, true]) {
    testWidgets('${adjusting ? "updated" : "new"} offer opens Mes offres after confirmation',
        (tester) async {
      final submissions = <RequestOptions>[];
      var submitted = false;
      api.dio.interceptors.clear();
      addTearDown(api.dio.interceptors.clear);
      api.dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
        if (request.method == 'POST' || request.method == 'PATCH') {
          submissions.add(request);
          submitted = true;
          handler.resolve(Response(requestOptions: request, statusCode: 200,
              data: {'offerId': 'offer-1'}));
        } else if (request.path == '/api/v1/driver/offers') {
          handler.resolve(Response(requestOptions: request, statusCode: 200,
              data: request.queryParameters['scope'] == 'active' && submitted
                  ? [{'offer_id': 'offer-1', 'booking_id': 'ride-1',
                      'pickup_address': 'Nice', 'dropoff_address': 'Cannes',
                      'status': 'ACTIVE', 'proposed_amount_minor': 3000}]
                  : <dynamic>[]));
        } else {
          handler.resolve(Response(requestOptions: request, statusCode: 200,
              data: {'pickup_address': 'Nice', 'dropoff_address': 'Cannes',
                'hasActiveOffer': adjusting, 'ownActiveOfferAmountMinor': 2500}));
        }
      }));
      final router = GoRouter(initialLocation: '/request', routes: [
        GoRoute(path: '/request', builder: (_, __) => const RequestScreen(bookingId: 'ride-1')),
        GoRoute(path: '/driver/offers', builder: (_, __) => const MesOffresScreen()),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(theme: veyraTheme(), routerConfig: router));
      await tester.pumpAndSettle();
      final amount = find.byType(TextField);
      await tester.scrollUntilVisible(amount, 180);
      if (adjusting) expect(tester.widget<TextField>(amount).controller!.text, '25,00');
      await tester.enterText(amount, '30,00');
      final send = find.text(adjusting ? 'Mettre à jour mon offre' : 'Envoyer mon offre');
      await tester.scrollUntilVisible(send, 180);
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(submissions, hasLength(1));
      expect(submissions.single.method, adjusting ? 'PATCH' : 'POST');
      expect(submissions.single.data['amountMinor'], 3000);
      expect(find.text(adjusting ? 'Offre mise à jour' : 'Offre envoyée'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(MesOffresScreen), findsOneWidget);
      expect(find.text('Nice → Cannes'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
