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
          data: request.path.endsWith('/offers') ? [
            {'offerId': 'offer-1', 'driverFirstName': 'Alexandre',
              'driverLastName': 'Martin', 'rating': 4.9, 'totalMinor': 3000},
            if(count>1) {'offerId': 'offer-2', 'driverFirstName': 'Emma',
              'driverLastName': 'Martin', 'rating': 4.8, 'totalMinor': 3200},
          ] : {
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
    // Board 05: the offers themselves are listed (no count header).
    expect(find.text('Alexandre Martin'), findsOneWidget);
    expect(find.text('Emma Martin'), findsNothing);
    count = 2;
    RefreshBus.bump();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Emma Martin'), 180,
        scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
    expect(find.text('Emma Martin'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
