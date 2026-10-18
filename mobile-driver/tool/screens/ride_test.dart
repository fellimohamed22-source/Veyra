import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/main.dart';
import 'package:veyra_driver/app/theme.dart';
import 'harness.dart';

Map<String, dynamic> _ride(String status) => {
      'id': 'r1', 'status': status, 'payment_method': 'CASH',
      'pickup_address': 'Paris, 16e arrondissement, Rue de la Paix, 75008 Paris', 'dropoff_address': 'Aéroport d’Orly (ORY), Terminal 4, 94390 Orly',
      'pickup_lat': 48.86, 'pickup_lng': 2.28, 'dropoff_lat': 48.72, 'dropoff_lng': 2.36,
      'scheduled_at': DateTime.now().add(const Duration(hours: 2, minutes: 10)).toUtc().toIso8601String(),
      'customer_name': 'Sophie M.', 'passenger_count': 3, 'baggage_count': 2, 'category_name': 'Berline',
      'vehicle_brand': 'Mercedes', 'vehicle_model': 'Classe E', 'plate_number': 'AB-123-CD',
      'customer_notes': 'Nous serons avec deux valises et un siège enfant.',
      'customer_total_amount_minor': 5200, 'driver_net_amount_minor': 4800, 'platform_commission_amount_minor': 400,
    };

void main() {
  setUpAll(loadAppFonts);
  testWidgets('ride confirmed', (tester) async {
    fakeApi((path, method, data) => path.endsWith('/estimate') ? {'distanceMeters': 18000, 'durationSeconds': 1500} : _ride('CONFIRMED'));
    await shot(tester, MaterialApp(theme: veyraTheme(), debugShowCheckedModeBanner: false, home: const RideScreen(bookingId: 'r1')), 'driver_13_ride');
  });
}
