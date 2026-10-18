import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:veyra_client/main.dart';
import 'package:veyra_client/app/theme.dart';
import 'harness.dart';

const _pickup = 'Paris, 8e arrondissement, Rue de la Paix, 75008 Paris';
const _dropoff = 'Aéroport Charles-de-Gaulle (CDG), Terminal 2E, 95700 Roissy';

Map<String, dynamic> _booking(String status, Duration left) => {
      'id': '1a2b3c4d-0000-0000-0000-000000000001',
      'status': status,
      'pickup_address': _pickup,
      'dropoff_address': _dropoff,
      'scheduled_at': DateTime.now().add(left).toUtc().toIso8601String(),
      'passenger_count': 2,
      'baggage_count': 3,
      'payment_method': 'ONLINE',
      'payment_status': 'CAPTURED',
      'offer_count': 3,
      'category_name': 'Confort',
      'customer_notes': 'Je serai devant l’entrée principale de l’hôtel, avec deux grandes valises.',
      if (status == 'OFFERS_RECEIVED') 'best_offer_total_minor': 5200,
      if (status != 'OFFERS_RECEIVED') ...{
        'selected_driver_id': 'd1',
        'driver_first_name': 'Thomas',
        'driver_last_name': 'Martin',
        'driver_rating': 4.9,
        'favorite_driver': true,
        'vehicle_brand': 'Mercedes',
        'vehicle_model': 'Classe E',
        'plate_number': 'AB-123-CD',
        'customer_total_amount_minor': 5200,
      },
    };

final _offers = [
  {'offerId': 'o1', 'driverId': 'd1', 'driverFirstName': 'Thomas', 'driverLastName': 'Martin', 'rating': 4.9,
    'vehicleBrand': 'Mercedes', 'vehicleModel': 'Classe E', 'vehicleCategory': 'Confort', 'vehicleColor': 'Noir', 'vehicleYear': 2023,
    'driverPriceMinor': 4800, 'commissionMinor': 400, 'commissionRateBps': 833, 'totalMinor': 5200, 'driverVerified': true},
  {'offerId': 'o2', 'driverId': 'd2', 'driverFirstName': 'Julien', 'driverLastName': 'Moreau', 'rating': 4.8,
    'vehicleBrand': 'Tesla', 'vehicleModel': 'Model 3', 'vehicleCategory': 'Électrique', 'totalMinor': 5600},
  {'offerId': 'o3', 'driverId': 'd3', 'driverFirstName': 'Sophie', 'driverLastName': 'Laurent', 'rating': 4.7,
    'vehicleBrand': 'Skoda', 'vehicleModel': 'Octavia', 'vehicleCategory': 'Confort', 'totalMinor': 5800},
];

Widget _app(Widget home) {
  final router = GoRouter(initialLocation: '/', routes: [
    GoRoute(path: '/', builder: (_, __) => home),
  ]);
  return MaterialApp.router(theme: veyraTheme(), routerConfig: router, debugShowCheckedModeBanner: false);
}

void _api(Map<String, dynamic> booking) => fakeApi((path, method, data) {
      if (path.endsWith('/offers')) return _offers;
      if (path.contains('favorite')) return [{'driver_id': 'd1'}];
      return booking;
    });

Future<void> _settle(WidgetTester t) async {
  for (var j = 0; j < 6; j++) {
    await t.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  setUpAll(loadAppFonts);
  testWidgets('offers list', (tester) async {
    _api(_booking('OFFERS_RECEIVED', const Duration(days: 2)));
    await shot(tester, _app(const OffersScreen(bookingId: 'b')), 'offers_01_list');
  });
  testWidgets('offer detail', (tester) async {
    _api(_booking('OFFERS_RECEIVED', const Duration(days: 2)));
    await shot(tester, _app(const OffersScreen(bookingId: 'b')), 'offers_02_detail', before: (t) async {
      await t.tap(find.text('Thomas Martin'));
      await _settle(t);
    });
  });
  testWidgets('offer confirm', (tester) async {
    _api(_booking('OFFERS_RECEIVED', const Duration(days: 2)));
    await shot(tester, _app(const OffersScreen(bookingId: 'b')), 'offers_03_confirm', before: (t) async {
      await t.tap(find.text('Thomas Martin'));
      await _settle(t);
      await t.tap(find.text('Choisir ce chauffeur'));
      await _settle(t);
    });
  });
  final details = {
    'detail_01_confirmed': _booking('CONFIRMED', const Duration(hours: 2, minutes: 45, seconds: 30)),
    'detail_02_soon': _booking('CONFIRMED', const Duration(minutes: 25, seconds: 30)),
    'detail_03_en_route': _booking('DRIVER_EN_ROUTE', const Duration(minutes: 8)),
    'detail_04_pending': _booking('OFFERS_RECEIVED', const Duration(days: 2)),
    'detail_05_completed': _booking('COMPLETED', const Duration(hours: -3)),
  };
  details.forEach((name, booking) {
    testWidgets(name, (tester) async {
      _api(booking);
      await shot(tester, _app(const BookingDetailScreen(bookingId: 'b')), name);
    });
  });
}
