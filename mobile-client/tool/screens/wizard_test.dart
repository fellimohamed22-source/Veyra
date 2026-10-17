import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:veyra_client/main.dart';
import 'package:veyra_client/app/theme.dart';
import 'harness.dart';

Object? _responses(String path, String method, Object? data) {
  if (path.contains('vehicle-categories')) {
    return [
      {'id': 'eco', 'code': 'ECONOMY', 'display_name': 'Économique', 'capacity': 4},
      {'id': 'std', 'code': 'STANDARD', 'display_name': 'Confort', 'capacity': 4},
      {'id': 'van', 'code': 'VAN', 'display_name': 'Van Confort', 'capacity': 7},
      {'id': 'vip', 'code': 'VAN_PREMIUM', 'display_name': 'Van Premium', 'capacity': 7},
      {'id': 'bp', 'code': 'PREMIUM', 'display_name': 'Berline Premium', 'capacity': 4},
    ];
  }
  if (path.contains('/me/addresses')) {
    return [
      {'id': 'h', 'label': 'Mon domicile', 'address': '12 rue des Lilas, 75015 Paris', 'lat': 48.84, 'lng': 2.29},
      {'id': 'w', 'label': 'Mon travail', 'address': 'Tour First, 92800 Puteaux', 'lat': 48.89, 'lng': 2.24},
    ];
  }
  if (path.contains('routes/estimate')) {
    return {'distanceMeters': 32000, 'durationSeconds': 2700, 'points': [
      {'lat': 48.869, 'lng': 2.331}, {'lat': 48.95, 'lng': 2.45}, {'lat': 49.009, 'lng': 2.547}]};
  }
  return [];
}

Widget _app() {
  final router = GoRouter(initialLocation: '/addresses', routes: [
    GoRoute(path: '/addresses', builder: (_, __) => const AddressScreen(initialBooking: {
      'pickup_address': 'Rue de la Paix, 75008 Paris', 'pickup_lat': 48.869, 'pickup_lng': 2.331,
      'dropoff_address': 'Aéroport Charles-de-Gaulle (CDG), Terminal 2E, 95700 Roissy', 'dropoff_lat': 49.009, 'dropoff_lng': 2.547,
      'category_id': 'std', 'passenger_count': 2, 'baggage_count': 3, 'payment_method': 'ONLINE',
      'customer_notes': 'Je serai devant l’entrée principale de l’hôtel, avec deux grandes valises. Merci de me contacter si besoin.',
    })),
    GoRoute(path: '/home', builder: (_, __) => const Scaffold(body: Text('Accueil'))),
  ]);
  return MaterialApp.router(theme: veyraTheme(), routerConfig: router, debugShowCheckedModeBanner: false);
}

Future<void> _next(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(find.text('Suivant'));
    for (var j = 0; j < 4; j++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }
}

void main() {
  setUpAll(loadAppFonts);
  final names = ['01_depart', '02_destination', '03_vehicule', '04_details', '05_commentaire', '06_recap'];
  for (var i = 0; i < names.length; i++) {
    testWidgets('wizard ${names[i]}', (tester) async {
      fakeApi(_responses);
      await shot(tester, _app(), 'wizard_${names[i]}', before: (t) => _next(t, i));
    });
  }
}
