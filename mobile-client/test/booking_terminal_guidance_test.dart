import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:veyra_client/main.dart';
import 'package:veyra_client/core/formatters/status_labels.dart';

void main() {
  for (final status in ['EXPIRED', 'NO_OFFER', 'CUSTOMER_NO_SHOW']) {
    testWidgets('$status shows its outcome and allows a new request', (tester) async {
      Map<String, dynamic>? rebook;
      final booking = {'status': status, 'payment_method': 'CASH',
        'pickup_address': 'Nice', 'dropoff_address': 'Cannes'};
      api.dio.interceptors.clear();
      addTearDown(api.dio.interceptors.clear);
      api.dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
        handler.resolve(Response(requestOptions: request, statusCode: 200, data: booking));
      }));
      final router = GoRouter(initialLocation: '/booking', routes: [
        GoRoute(path: '/booking', builder: (_, __) => const BookingDetailScreen(bookingId: 'ride-1')),
        GoRoute(path: '/addresses', builder: (_, state) {
          rebook = Map<String, dynamic>.from(state.extra! as Map);
          return const Scaffold(body: Text('Nouvelle demande'));
        }),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text(VeyraStatusLabels.bookingStatus(status)), findsOneWidget);
      final again = find.text('Réserver à nouveau');
      await tester.scrollUntilVisible(again, 180);
      expect(find.text('Bon à savoir'), findsNothing);
      expect(find.text('Afficher le PIN'), findsNothing);
      expect(find.text('Annuler la réservation'), findsNothing);
      await tester.tap(again);
      await tester.pumpAndSettle();
      expect(rebook, booking);
      expect(find.text('Nouvelle demande'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
