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
        } else if (request.path.endsWith('/onboarding/status')) {
          handler.resolve(Response(requestOptions: request, statusCode: 200, data: {'vehicles': [
            {'id': 'v-1', 'status': 'APPROVED', 'category_id': 'cat', 'brand': 'Mercedes', 'model': 'Classe E', 'category_name': 'Confort', 'seats': 4, 'baggage_capacity': 3},
          ]}));
        } else if (request.path.endsWith('/quote')) {
          final net = request.queryParameters['amountMinor'] as int;
          handler.resolve(Response(requestOptions: request, statusCode: 200,
              data: {'driverNetMinor': net, 'commissionRateBps': 1000, 'commissionMinor': net ~/ 10, 'customerTotalMinor': net + net ~/ 10}));
        } else if (request.path.endsWith('/suggested-price')) {
          handler.resolve(Response(requestOptions: request, statusCode: 200, data: {'available': false}));
        } else {
          handler.resolve(Response(requestOptions: request, statusCode: 200,
              data: {'pickup_address': 'Nice', 'dropoff_address': 'Cannes', 'category_id': 'cat',
                'scheduled_at': DateTime.now().add(const Duration(days: 2)).toUtc().toIso8601String(),
                'hasActiveOffer': adjusting, 'ownActiveOfferAmountMinor': 2500}));
        }
      }));
      final router = GoRouter(initialLocation: '/request', routes: [
        GoRoute(path: '/request', builder: (_, __) => const RequestScreen(bookingId: 'ride-1')),
        GoRoute(path: '/driver/offers', builder: (_, __) => const MesOffresScreen()),
        GoRoute(path: '/requests', builder: (_, __) => const Scaffold(body: Text('Demandes'))),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(theme: veyraTheme(), routerConfig: router));
      await tester.pumpAndSettle();
      // Board 14: detail → create → summary → sent.
      await tester.tap(find.text(adjusting ? 'Modifier mon offre' : 'Créer mon offre'));
      await tester.pumpAndSettle();
      final amount = find.byKey(const ValueKey('offer-amount'));
      if (adjusting) expect(tester.widget<TextField>(amount).controller!.text, '25,00');
      await tester.enterText(amount, '30,00');
      if (!adjusting) {
        await tester.scrollUntilVisible(find.byKey(const ValueKey('offer-message')), 200, scrollable: find.descendant(of: find.byType(ListView).last, matching: find.byType(Scrollable)).first);
        await tester.enterText(find.byKey(const ValueKey('offer-message')), 'Je serai à l’heure.');
      }
      await tester.tap(find.text(adjusting ? 'Mettre à jour mon offre' : 'Envoyer mon offre'));
      await tester.pumpAndSettle();
      expect(submissions, isEmpty, reason: 'the summary comes first');
      expect(find.text('Récapitulatif de l’offre'), findsOneWidget);
      expect(find.textContaining('33,00 €', findRichText: true), findsWidgets);
      await tester.tap(find.text('Confirmer et envoyer'));
      await tester.pumpAndSettle();
      expect(submissions, hasLength(1));
      expect(submissions.single.method, adjusting ? 'PATCH' : 'POST');
      expect(submissions.single.data['amountMinor'], 3000);
      if (!adjusting) {
        expect(submissions.single.data['vehicleId'], 'v-1');
        expect(submissions.single.data['message'], 'Je serai à l’heure.');
      }
      expect(find.text(adjusting ? 'Votre offre a été mise à jour !' : 'Votre offre a été envoyée avec succès !'), findsOneWidget);
      await tester.tap(find.text('Voir mes offres'));
      await tester.pumpAndSettle();
      expect(find.byType(MesOffresScreen), findsOneWidget);
      expect(find.text('Nice → Cannes'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
