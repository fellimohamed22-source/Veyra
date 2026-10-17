import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/main.dart';
import 'package:veyra_client/app/theme.dart';
import 'harness.dart';

String _at(int hours) => DateTime.now().add(Duration(hours: hours)).toUtc().toIso8601String();

final _bookings = [
  {'id': 'b1', 'status': 'OFFERS_RECEIVED', 'pickup_address': 'Paris, France', 'dropoff_address': 'Aéroport Charles-de-Gaulle (CDG), Roissy',
   'scheduled_at': _at(30), 'passenger_count': 2, 'baggage_count': 3, 'offer_count': 3, 'best_offer_total_minor': 5280},
  {'id': 'b2', 'status': 'OPEN_FOR_OFFERS', 'pickup_address': 'Lyon, France', 'dropoff_address': 'Aéroport Saint-Exupéry, Colombier-Saugnieu',
   'scheduled_at': _at(60), 'passenger_count': 1, 'baggage_count': 3, 'offer_count': 0},
  {'id': 'b3', 'status': 'CONFIRMED', 'pickup_address': 'Paris, France', 'dropoff_address': 'Versailles, France',
   'scheduled_at': _at(80), 'passenger_count': 1, 'baggage_count': 2, 'selected_driver_id': 'd1', 'driver_name': 'Thomas Martin'},
  {'id': 'b4', 'status': 'COMPLETED', 'pickup_address': 'Nice, France', 'dropoff_address': 'Cannes, France',
   'scheduled_at': _at(-48), 'passenger_count': 1, 'baggage_count': 0, 'selected_driver_id': 'd2', 'driver_name': 'Julien Moreau'},
];

Object? _responses(String path, String method, Object? data) {
  if (path.endsWith('/me')) {
    return {'first_name': 'Sophie', 'last_name': 'Bernard', 'email': 'sophie.bernard@email.fr', 'phone': '+33 6 12 34 56 78'};
  }
  if (path.contains('scheduled-bookings')) return _bookings;
  return [];
}

Widget _app(String location) {
  router.go(location);
  return MaterialApp.router(theme: veyraTheme(), routerConfig: router, debugShowCheckedModeBanner: false);
}

void main() {
  setUpAll(loadAppFonts);
  for (final (name, location) in [
    ('home_accueil', '/home'),
    ('home_mes_demandes', '/bookings'),
    ('home_mes_reservations', '/reservations'),
    ('home_profil', '/account'),
  ]) {
    testWidgets(name, (tester) async {
      fakeApi(_responses);
      await shot(tester, _app(location), name);
    });
  }
}
