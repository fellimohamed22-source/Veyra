import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/main.dart';
import 'package:veyra_driver/app/theme.dart';
import 'package:veyra_driver/ui/driver_home_screen.dart';
import 'harness.dart';

String _in(Duration d) => DateTime.now().add(d).toUtc().toIso8601String();

final _requests = [
  {'id': 'b1', 'scheduled_at': _in(const Duration(hours: 3)), 'pickup_address': 'Paris, 16e arrondissement', 'dropoff_address': 'Aéroport d’Orly (ORY)',
    'passenger_count': 3, 'baggage_count': 2, 'customer_favorite': true, 'best_other_offer_minor': 4800, 'category_name': 'Berline – Confort'},
  {'id': 'b2', 'scheduled_at': _in(const Duration(days: 1, hours: 2)), 'pickup_address': 'Paris, 8e arrondissement', 'dropoff_address': 'Aéroport CDG (Terminal 2E)',
    'passenger_count': 2, 'baggage_count': 3, 'best_other_offer_minor': 5200, 'category_name': 'Berline – Confort'},
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
  testWidgets('driver home', (tester) async {
    fakeApi(_responses);
    await shot(tester, _app(DriverHomeScreen(api: api, go: (_) {}, push: (_) {})), 'driver_02_home');
  });
  testWidgets('driver requests', (tester) async {
    fakeApi(_responses);
    await shot(tester, _app(const OpportunitiesScreen()), 'driver_03_requests');
  });
}
