import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:veyra_client/main.dart';
import 'package:veyra_client/app/theme.dart';
import 'package:veyra_client/core/widgets/notifications_view.dart';

/// Board screens stay readable on a small phone with text enlarged 1.5x.
void main() {
  String inH(int h) => DateTime.now().add(Duration(hours: h)).toUtc().toIso8601String();
  Map<String, dynamic> booking(String status) => {
        'id': '1a2b3c4d-0000-0000-0000-000000000001', 'status': status, 'payment_method': 'ONLINE', 'payment_status': 'CAPTURED',
        'pickup_address': 'Paris, 16e arrondissement, avenue Victor Hugo, 75116 Paris',
        'dropoff_address': 'Aéroport Charles-de-Gaulle (CDG), Terminal 2E, 95700 Roissy',
        'scheduled_at': inH(26), 'offer_window_ends_at': inH(20), 'passenger_count': 7, 'baggage_count': 12, 'offer_count': 12,
        'best_offer_total_minor': 1234567, 'category_name': 'Van Premium', 'customer_notes': 'Deux grandes valises et un siège enfant, merci.',
        'selected_driver_id': 'd1', 'driver_first_name': 'Jean-Christophe', 'driver_last_name': 'de la Fontaine', 'driver_rating': 4.9,
        'driver_verified': true, 'favorite_driver': true, 'vehicle_brand': 'Mercedes-Benz', 'vehicle_model': 'Classe V Avantgarde',
        'plate_number': 'AB-123-CD', 'customer_total_amount_minor': 1234567,
      };
  Object? respond(RequestOptions r) {
    final p = r.path;
    if (p.endsWith('/me')) return {'first_name': 'Jean-Christophe', 'last_name': 'de la Fontaine', 'email': 'jean-christophe.delafontaine@example.com', 'phone': '+33612345678'};
    if (p.endsWith('/notifications')) {
      return [{'id': 'n1', 'template_code': 'NEW_OFFER', 'unread': true, 'created_at': DateTime.now().toUtc().toIso8601String(), 'data': '{"bookingId":"b"}',
        'pickup_address': 'Paris, 16e arrondissement, avenue Victor Hugo', 'dropoff_address': 'Aéroport Charles-de-Gaulle (CDG)', 'scheduled_at': inH(26)}];
    }
    if (p.endsWith('/unread-count')) return {'unread': 12};
    if (p.contains('/scheduled-bookings/') && !p.endsWith('/offers')) return booking(r.extra['status'] as String? ?? 'CONFIRMED');
    if (p.contains('scheduled-bookings') || p.contains('/bookings')) return [booking('OFFERS_RECEIVED'), booking('CONFIRMED'), booking('COMPLETED')];
    return [];
  }

  final screens = <String, (Widget Function(), String)>{
    'accueil': (() => const AccueilScreen(), 'CONFIRMED'),
    'mes demandes': (() => const HomeScreen(), 'CONFIRMED'),
    'mes réservations': (() => const ReservationsScreen(), 'CONFIRMED'),
    'profil': (() => const AccountScreen(), 'CONFIRMED'),
    'ma réservation confirmée': (() => const BookingDetailScreen(bookingId: 'b'), 'CONFIRMED'),
    'ma demande avec offres': (() => const BookingDetailScreen(bookingId: 'b'), 'OFFERS_RECEIVED'),
    'ma réservation terminée': (() => const BookingDetailScreen(bookingId: 'b'), 'COMPLETED'),
    'notifications': (() => VeyraNotificationsScreen(load: () => api.notifications(), markRead: api.markNotificationRead, markAllRead: api.markAllNotificationsRead, open: (_) {}), 'CONFIRMED'),
    'inscription': (() => const RegisterScreen(), 'CONFIRMED'),
  };

  screens.forEach((name, entry) {
    testWidgets('$name fits 320 px with 1.5x text', (tester) async {
      tester.view.physicalSize = const Size(320, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      FlutterSecureStorage.setMockInitialValues({});
      api.dio.interceptors.clear();
      addTearDown(api.dio.interceptors.clear);
      api.dio.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
        r.extra['status'] = entry.$2;
        h.resolve(Response(requestOptions: r, statusCode: 200, data: respond(r)));
      }));
      final router = GoRouter(routes: [GoRoute(path: '/', builder: (_, __) => entry.$1())]);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(
        theme: veyraTheme(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.5)), child: child!),
      ));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
