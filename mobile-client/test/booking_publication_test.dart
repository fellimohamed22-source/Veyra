import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:veyra_client/main.dart';
import 'package:veyra_client/core/widgets/booking_route_preview.dart';
import 'package:veyra_client/app/theme.dart';

void main() {
  setUp(() => BookingRoutePreview.enableNetworkTiles = false);
  tearDown(() => BookingRoutePreview.enableNetworkTiles = true);
  testWidgets('publication fits enlarged text and opens its pending request', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final initial = <String, dynamic>{'category_id': 'standard',
      'category_name': 'Berline', 'passenger_count': 2, 'baggage_count': 1,
      'payment_method': 'CASH', 'customer_notes': 'Siège enfant',
      'pickup_address': 'Nice', 'pickup_lat': 43.7, 'pickup_lng': 7.2,
      'dropoff_address': 'Cannes', 'dropoff_lat': 43.5, 'dropoff_lng': 7.0};
    final posts = <RequestOptions>[];
    String? openedId;
    api.dio.interceptors.clear();
    addTearDown(api.dio.interceptors.clear);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      if (request.method == 'POST') {
        posts.add(request);
        handler.resolve(Response(requestOptions: request, statusCode: 201,
            data: {'id': 'new-booking'}));
      } else if (request.path.endsWith('/new-booking')) {
        handler.resolve(Response(requestOptions: request, statusCode: 200,
            data: {...initial, 'status': 'OPEN_FOR_OFFERS',
              'passenger_count': posts.single.data['passengerCount'],
              'scheduled_at': posts.single.data['scheduledAt'],
              'offer_window_ends_at': DateTime.now().add(const Duration(hours: 1)).toUtc().toIso8601String()}));
      } else {
        handler.resolve(Response(requestOptions: request, statusCode: 200,
            data: [{'id': 'standard', 'display_name': 'Berline', 'capacity': 4}]));
      }
    }));
    final router = GoRouter(initialLocation: '/addresses', routes: [
      GoRoute(path: '/addresses', builder: (_, __) => AddressScreen(initialBooking: initial)),
      GoRoute(path: '/home', builder: (_, __) => const Scaffold(body: Text('Accueil'))),
      GoRoute(path: '/booking/:id', builder: (_, state) {
        openedId = state.pathParameters['id'];
        return BookingDetailScreen(bookingId: openedId!);
      }),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(theme: veyraTheme(), routerConfig: router,
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.5)), child: child!)));
    await tester.pumpAndSettle();
    // The route preview contains a FlutterMap that consumes drag gestures.
    // Move the form's own ScrollPosition directly instead of dragging on
    // the map; ListView builds off-screen children as its offset changes.
    final formScroll = find.descendant(
        of: find.byType(AddressScreen), matching: find.byType(Scrollable)).first;
    final position = tester.state<ScrollableState>(formScroll).position;
    Future<void> reveal(Finder target) async {
      for (var i = 0; i < 80 && target.evaluate().isEmpty; i++) {
        if (position.pixels >= position.maxScrollExtent) break;
        position.jumpTo((position.pixels + 100)
            .clamp(position.minScrollExtent, position.maxScrollExtent));
        await tester.pump();
      }
      expect(target, findsWidgets,
          reason: 'Control not found after scrolling the booking ListView');
      await tester.ensureVisible(target.first);
      await tester.pumpAndSettle();
    }
    await reveal(find.text('Passagers'));
    await reveal(find.byTooltip('Augmenter'));
    await tester.tap(find.byTooltip('Augmenter').first);
    await tester.pumpAndSettle();
    await reveal(find.text('Récapitulatif'));
    final recap = find.ancestor(of: find.text('Récapitulatif'), matching: find.byType(Card)).first;
    expect(find.descendant(of: recap, matching: find.text('Nice')), findsOneWidget);
    expect(find.descendant(of: recap, matching: find.text('Cannes')), findsOneWidget);
    expect(find.descendant(of: recap, matching: find.text('Berline')), findsOneWidget);
    expect(find.descendant(of: recap, matching: find.text('3 passager(s) • 1 bagage(s)')), findsOneWidget);
    expect(find.descendant(of: recap, matching: find.text('Siège enfant')), findsOneWidget);
    await reveal(find.text('Publier la demande'));
    await tester.tap(find.text('Publier la demande'));
    await tester.pumpAndSettle();
    expect(find.text('Vérifiez votre demande'), findsOneWidget);
    await tester.ensureVisible(find.text('Confirmer et publier'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmer et publier'));
    await tester.pumpAndSettle();
    expect(posts, hasLength(1));
    final body = Map<String, dynamic>.from(posts.single.data as Map);
    expect(body['pickup']['address'], 'Nice');
    expect(body['dropoff']['address'], 'Cannes');
    expect(body['passengerCount'], 3);
    expect(body['baggageCount'], 1);
    expect(body['paymentMethod'], 'CASH');
    expect(body['customerNotes'], 'Siège enfant');
    expect(DateTime.parse(body['scheduledAt']).isUtc, isTrue);
    expect(posts.single.headers['Idempotency-Key'], isNotEmpty);
    expect(find.text('Demande publiée'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Voir ma demande'));
    await tester.tap(find.text('Voir ma demande'));
    await tester.pumpAndSettle();
    expect(openedId, 'new-booking');
    expect(find.byType(BookingDetailScreen), findsOneWidget);
    expect(find.text('Voir les offres'), findsOneWidget);
    expect(find.textContaining('Réception des offres jusqu’au'), findsOneWidget);
    expect(posts, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
