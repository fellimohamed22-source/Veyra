import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/main.dart';
import 'package:veyra_client/app/theme.dart';
import 'harness.dart';

/// Board 10 P4 « Course en cours ».
void main() {
  setUpAll(loadAppFonts);
  testWidgets('live ride', (tester) async {
    final now = DateTime.now().toUtc();
    fakeApi((path, method, data) {
      if (path.endsWith('/location')) {
        return {'available': true, 'lat': 48.97, 'lng': 2.52, 'heading': 40, 'recorded_at': now.toIso8601String()};
      }
      if (path.contains('/routes/estimate')) {
        return {'distanceMeters': 4800, 'durationSeconds': 480, 'points': [
          {'lat': 48.8686, 'lng': 2.3311}, {'lat': 48.90, 'lng': 2.38}, {'lat': 48.93, 'lng': 2.45}, {'lat': 48.97, 'lng': 2.52}, {'lat': 49.0097, 'lng': 2.5479}]};
      }
      return {
        'id': '1a2b3c4d-0000-0000-0000-000000000000', 'status': 'DRIVER_EN_ROUTE',
        'pickup_address': 'Paris, 8e arrondissement, Rue de la Paix, 75008 Paris', 'dropoff_address': 'Aéroport Charles-de-Gaulle (CDG), Terminal 2E, 95700 Roissy',
        'pickup_lat': 48.8686, 'pickup_lng': 2.3311, 'dropoff_lat': 49.0097, 'dropoff_lng': 2.5479,
        'scheduled_at': now.add(const Duration(minutes: 20)).toIso8601String(), 'passenger_count': 2, 'baggage_count': 3,
        'customer_notes': 'Je serai devant l’entrée principale de l’hôtel, avec deux grandes valises.',
        'driver_first_name': 'Thomas', 'driver_last_name': 'Martin', 'driver_rating': 4.9, 'favorite_driver': true,
        'vehicle_brand': 'Mercedes', 'vehicle_model': 'Classe E', 'category_name': 'Confort', 'plate_number': 'AB-123-CD',
      };
    });
    await shot(tester, MaterialApp(theme: veyraTheme(), debugShowCheckedModeBanner: false, home: const LiveLocationScreen(bookingId: 'b1')), 'live_01_course_en_cours');
  });
}
