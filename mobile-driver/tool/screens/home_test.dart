import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/main.dart';
import 'package:veyra_driver/app/theme.dart';
import 'package:veyra_driver/ui/driver_home_screen.dart';
import 'package:veyra_driver/ui/driver_profile.dart';
import 'harness.dart';

String _in(Duration d) => DateTime.now().add(d).toUtc().toIso8601String();

final _requests = [
  {'id': 'b1', 'scheduled_at': _in(const Duration(hours: 3)), 'pickup_address': 'Paris, 16e arrondissement', 'dropoff_address': 'Aéroport d’Orly (ORY)',
    'passenger_count': 3, 'baggage_count': 2, 'customer_favorite': true, 'best_other_offer_minor': 4800, 'category_name': 'Berline – Confort', 'customer_display_name': 'Sophie M.', 'customer_rating': 4.9, 'customer_rating_count': 210},
  {'id': 'b2', 'scheduled_at': _in(const Duration(days: 1, hours: 2)), 'pickup_address': 'Paris, 8e arrondissement', 'dropoff_address': 'Aéroport CDG (Terminal 2E)',
    'passenger_count': 2, 'baggage_count': 3, 'best_other_offer_minor': 5200, 'category_name': 'Berline – Confort', 'customer_display_name': 'Ahmed T.', 'customer_rating': 4.7, 'customer_rating_count': 86},
  {'id': 'b3', 'scheduled_at': _in(const Duration(days: 2, hours: 5)), 'pickup_address': 'Neuilly-sur-Seine', 'dropoff_address': 'Paris Expo Porte de Versailles',
    'passenger_count': 4, 'baggage_count': 4, 'category_name': 'Van – Confort'},
];

Object? _responses(String path, String method, Object? data) {
  if (path.endsWith('/dashboard')) {
    return {
      'acceptingRequests': true, 'availableRequests': 5, 'pendingOffers': 2, 'upcomingRides': 1,
      'nextRide': {'id': 'r1', 'status': 'CONFIRMED', 'scheduled_at': _in(const Duration(hours: 2, minutes: 10)), 'pickup_address': 'Paris, 8e arrondissement',
        'dropoff_address': 'Aéroport CDG (Terminal 2E)', 'passenger_count': 2, 'baggage_count': 3},
    };
  }
  if (path.endsWith('/availability')) return {'acceptingRequests': true};
  if (path.contains('vehicle-categories')) return [];
  return _requests;
}

Widget _app(Widget home) => MaterialApp(theme: veyraTheme(), home: home, debugShowCheckedModeBanner: false);

void main() {
  setUpAll(loadAppFonts);
  moreScreens();
  testWidgets('driver home', (tester) async {
    fakeApi(_responses);
    await shot(tester, _app(DriverHomeScreen(api: api, go: (_) {}, push: (_) {})), 'driver_02_home');
  });
  testWidgets('driver requests', (tester) async {
    fakeApi(_responses);
    await shot(tester, _app(const OpportunitiesScreen()), 'driver_03_requests');
  });
}

// Lot « Mes offres / Mes courses / Revenus / Profil » (boards 12, 13, 14).
Object? _more(String path, String method, Object? data) {
  if (path.endsWith('/driver/offers')) {
    return [
      {'offer_id': 'o1', 'booking_id': 'b1', 'status': 'ACTIVE', 'expires_at': _in(const Duration(minutes: 29)), 'scheduled_at': _in(const Duration(days: 1)),
        'pickup_address': 'Paris', 'dropoff_address': 'CDG', 'passenger_count': 2, 'baggage_count': 3, 'proposed_amount_minor': 4800, 'customer_total_minor': 5184,
        'vehicle_brand': 'Mercedes', 'vehicle_model': 'Classe E', 'vehicle_category': 'Confort'},
    ];
  }
  if (path.endsWith('/driver/bookings')) {
    return [
      {'id': 'r1', 'status': 'IN_PROGRESS', 'scheduled_at': _in(const Duration(minutes: 10)), 'pickup_address': 'Paris', 'dropoff_address': 'Orly',
        'passenger_count': 3, 'baggage_count': 2, 'category_name': 'Berline – Confort', 'driver_net_amount_minor': 5200},
      {'id': 'r2', 'status': 'CONFIRMED', 'scheduled_at': _in(const Duration(days: 1)), 'pickup_address': 'Neuilly', 'dropoff_address': 'Versailles',
        'passenger_count': 2, 'baggage_count': 3, 'category_name': 'Van – Confort', 'driver_net_amount_minor': 6000},
    ];
  }
  if (path.endsWith('/driver/wallet')) return {'onlinePayableMinor': 25000, 'cashDebtMinor': 0, 'monthEarningsMinor': 125000};
  if (path.endsWith('/transactions')) return [];
  if (path.endsWith('/me')) return {'first_name': 'Karim', 'last_name': 'B.', 'rating_average': 4.8, 'rating_count': 120};
  if (path.endsWith('/onboarding/status')) {
    return {'kyc_status': 'APPROVED', 'vehicles': [
      {'id': 'v1', 'status': 'APPROVED', 'brand': 'Mercedes', 'model': 'Classe E', 'category_name': 'Berline – Confort', 'seats': 4, 'baggage_capacity': 3, 'plate_number': 'AB-123-CD'},
      {'id': 'v2', 'status': 'APPROVED', 'brand': 'Mercedes', 'model': 'Classe V', 'category_name': 'Van – Confort', 'seats': 7, 'baggage_capacity': 6, 'plate_number': 'CD-456-EF'},
    ]};
  }
  return _responses(path, method, data);
}

void moreScreens() {
  testWidgets('driver my offers', (tester) async {
    fakeApi(_more);
    await shot(tester, _app(const MesOffresScreen()), 'driver_08_offers');
  });
  testWidgets('driver my rides', (tester) async {
    fakeApi(_more);
    await shot(tester, _app(const AgendaScreen()), 'driver_09_rides');
  });
  testWidgets('driver earnings', (tester) async {
    fakeApi(_more);
    await shot(tester, _app(const WalletScreen()), 'driver_10_earnings');
  });
  testWidgets('driver profile', (tester) async {
    fakeApi(_more);
    await shot(tester, _app(DriverProfileScreen(api: api, go: (_) {}, push: (_) {}, logout: () async {})), 'driver_11_profile');
  });
  testWidgets('driver vehicles', (tester) async {
    fakeApi(_more);
    await shot(tester, _app(DriverVehiclesScreen(api: api, push: (_) {})), 'driver_12_vehicles');
  });
}
