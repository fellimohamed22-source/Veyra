import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:veyra_client/main.dart';

void main() {
  testWidgets('pending booking count refreshes and opens its own offers', (tester) async {
    var count = 2;
    String? offersId;
    api.dio.interceptors.clear();
    addTearDown(api.dio.interceptors.clear);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      handler.resolve(Response(requestOptions: request, statusCode: 200,
          data: request.path.endsWith('/offers') ? <dynamic>[] : {
            'status': 'OFFERS_RECEIVED', 'offer_count': count,
            'payment_method': 'CASH', 'pickup_address': 'Nice',
            'dropoff_address': 'Cannes'}));
    }));
    final router = GoRouter(initialLocation: '/booking', routes: [
      GoRoute(path: '/booking', builder: (_, __) => const BookingDetailScreen(bookingId: 'ride-1')),
      GoRoute(path: '/offers/:id', builder: (_, state) {
        offersId = state.pathParameters['id'];
        return OffersScreen(bookingId: offersId!);
      }),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('2 offres reçues'), findsOneWidget);
    count = 1;
    RefreshBus.bump();
    await tester.pumpAndSettle();
    expect(find.text('1 offre reçue'), findsOneWidget);
    expect(find.text('2 offres reçues'), findsNothing);
    await tester.tap(find.text('Voir les offres'));
    await tester.pumpAndSettle();
    expect(offersId, 'ride-1');
    expect(find.byType(OffersScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
