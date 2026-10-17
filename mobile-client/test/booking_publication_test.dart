import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:veyra_client/main.dart';
import 'package:veyra_client/app/theme.dart';

void main() {
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
    Future<void> next() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Suivant'));
      await tester.pumpAndSettle();
    }
    await next(); // départ -> destination
    await next(); // destination -> véhicule
    await next(); // véhicule -> détails
    await tester.ensureVisible(find.byTooltip('Augmenter').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Augmenter').first);
    await tester.pumpAndSettle();
    await next(); // détails -> commentaire
    await next(); // commentaire -> récapitulatif
    expect(find.text('Récapitulatif de votre demande'), findsOneWidget);
    expect(find.text('Nice'), findsOneWidget);
    expect(find.text('Cannes'), findsOneWidget);
    expect(find.text('Berline'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    // At 150 % text on a 320 pt screen the comment is below the fold.
    await tester.scrollUntilVisible(find.text('Siège enfant'), 200,
        scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
    expect(find.text('Siège enfant'), findsOneWidget);
    await tester.tap(find.text('Rechercher des offres'));
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
    expect(find.text('Votre demande a été envoyée !'), findsOneWidget);
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
