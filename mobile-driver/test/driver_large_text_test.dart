import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/main.dart';
import 'package:veyra_driver/app/theme.dart';
import 'package:veyra_driver/ui/driver_home_screen.dart';
import 'package:veyra_driver/ui/driver_profile.dart';

/// Board screens stay readable on a small phone with text enlarged 1.5x.
void main() {
  String inH(int h) => DateTime.now().add(Duration(hours: h)).toUtc().toIso8601String();
  final detail = <String, dynamic>{'id': 'b1', 'scheduled_at': inH(30), 'offer_window_ends_at': inH(20), 'category_id': 'c', 'category_name': 'Berline – Confort',
    'pickup_address': 'Paris, 16e arrondissement, avenue Victor Hugo, 75116 Paris', 'dropoff_address': 'Aéroport d’Orly (ORY), Terminal 4, 94390 Orly',
    'pickup_lat': 48.86, 'pickup_lng': 2.28, 'dropoff_lat': 48.72, 'dropoff_lng': 2.36, 'passenger_count': 3, 'baggage_count': 2,
    'customer_notes': 'Nous serons avec deux grandes valises et un siège enfant, merci.', 'customer_favorite': true, 'currentBestOtherOfferMinor': 123456,
    'hasActiveOffer': true, 'ownActiveOfferAmountMinor': 129900, 'has_eligible_vehicle': true};
  Object? respond(RequestOptions r) {
    final p = r.path;
    if (p.endsWith('/dashboard')) {
      return {'acceptingRequests': true, 'availableRequests': 12, 'pendingOffers': 3, 'upcomingRides': 2,
        'nextRide': {'id': 'r1', 'scheduled_at': inH(3), 'pickup_address': 'Paris, 16e arrondissement, avenue Victor Hugo',
          'dropoff_address': 'Aéroport Charles-de-Gaulle (CDG), Terminal 2E', 'passenger_count': 4, 'baggage_count': 6}};
    }
    if (p.endsWith('/availability')) return {'acceptingRequests': true};
    if (p.endsWith('/driver/offers')) {
      return [{'offer_id': 'o1', 'booking_id': 'b1', 'status': 'ACTIVE', 'expires_at': inH(1), 'scheduled_at': inH(20),
        'pickup_address': 'Boulogne-Billancourt', 'dropoff_address': 'Aéroport Beauvais-Tillé (BVA)', 'passenger_count': 2, 'baggage_count': 2,
        'proposed_amount_minor': 123456, 'customer_total_minor': 133333, 'vehicle_brand': 'Mercedes-Benz', 'vehicle_model': 'Classe V Avantgarde', 'vehicle_category': 'Van Premium'}];
    }
    if (p.endsWith('/driver/bookings')) {
      return [{'id': 'r1', 'status': 'CONFIRMED', 'scheduled_at': inH(26), 'pickup_address': 'Neuilly-sur-Seine', 'dropoff_address': 'Disneyland Paris',
        'passenger_count': 7, 'baggage_count': 6, 'category_name': 'Van Premium', 'driver_net_amount_minor': 123456}];
    }
    if (p.endsWith('/driver/wallet')) return {'onlinePayableMinor': 1234567, 'cashDebtMinor': 12000, 'monthEarningsMinor': 9876543, 'cashWarning': true,
      'cashWarningThresholdMinor': 5000, 'cashRestrictedThresholdMinor': 10000, 'cashBlockedThresholdMinor': 15000};
    if (p.endsWith('/transactions')) return [];
    if (p.endsWith('/me')) return {'first_name': 'Jean-Christophe', 'last_name': 'de la Fontaine', 'rating_average': 4.9, 'rating_count': 1234};
    if (p.endsWith('/onboarding/status')) return {'kyc_status': 'APPROVED', 'vehicles': [{'id': 'v1', 'status': 'APPROVED', 'category_id': 'c', 'brand': 'Mercedes-Benz', 'model': 'Classe E Avantgarde Line', 'category_name': 'Berline – Confort', 'seats': 4, 'baggage_capacity': 3}]};
    if (p.endsWith('/unread-count')) return {'unread': 12};
    if (p.endsWith('/quote')) return {'driverNetMinor': 123456, 'commissionRateBps': 1250, 'commissionMinor': 15432, 'customerTotalMinor': 138888};
    if (p.endsWith('/suggested-price')) return {'available': true, 'netLowMinor': 104500, 'netHighMinor': 126000};
    if (p.endsWith('/estimate')) return {'distanceMeters': 123400, 'durationSeconds': 5400};
    if (p.contains('/driver/opportunities/')) return detail;
    if (p.contains('vehicle-categories')) return [];
    return [
      {'id': 'b1', 'scheduled_at': inH(4), 'pickup_address': 'Paris, 16e arrondissement, avenue Victor Hugo', 'dropoff_address': 'Aéroport d’Orly (ORY), Terminal 4',
        'passenger_count': 3, 'baggage_count': 2, 'customer_favorite': true, 'best_other_offer_minor': 123456, 'category_name': 'Berline – Confort', 'own_offer_amount_minor': 99900},
    ];
  }

  final screens = <String, Widget Function()>{
    'request detail': () => const RequestScreen(bookingId: 'b1'),
    'offer composer': () => OfferComposerScreen(bookingId: 'b1', request: detail),
    'home': () => DriverHomeScreen(api: api, go: (_) {}, push: (_) {}),
    'requests': () => const OpportunitiesScreen(),
    'offers': () => const MesOffresScreen(),
    'rides': () => const AgendaScreen(),
    'earnings': () => const WalletScreen(),
    'profile': () => DriverProfileScreen(api: api, go: (_) {}, push: (_) {}, logout: () async {}),
  };

  screens.forEach((name, build) {
    testWidgets('$name fits 320 px with 1.5x text', (tester) async {
      tester.view.physicalSize = const Size(320, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      api.dio.interceptors.clear();
      addTearDown(api.dio.interceptors.clear);
      api.dio.interceptors.add(InterceptorsWrapper(onRequest: (r, h) => h.resolve(Response(requestOptions: r, statusCode: 200, data: respond(r)))));
      await tester.pumpWidget(MaterialApp(
        theme: veyraTheme(),
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.5)), child: child!),
        home: build(),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
