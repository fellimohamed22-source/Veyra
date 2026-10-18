import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/main.dart';
import 'package:veyra_driver/app/theme.dart';
import 'harness.dart';

final _request = {
  'id': '9f3a2c1d-0000-0000-0000-000000000001',
  'pickup_address': 'Paris, 8e arrondissement, Rue de la Paix, 75008 Paris',
  'dropoff_address': 'Aéroport Charles-de-Gaulle (CDG), Terminal 2E, 95700 Roissy',
  'scheduled_at': DateTime.now().add(const Duration(days: 3)).toUtc().toIso8601String(),
  'offer_window_ends_at': DateTime.now().add(const Duration(days: 2)).toUtc().toIso8601String(),
  'pickup_lat': 48.869, 'pickup_lng': 2.331, 'dropoff_lat': 49.009, 'dropoff_lng': 2.547,
  'passenger_count': 2, 'baggage_count': 3, 'category_id': 'cat', 'category_name': 'Confort',
  'customer_notes': 'Je serai devant l’entrée principale de l’hôtel, avec deux grandes valises.',
  'customer_favorite': true, 'currentBestOtherOfferMinor': 5200, 'has_eligible_vehicle': true,
};

Object? _responses(String path, String method, Object? data) {
  if (path.endsWith('/estimate')) {
    return {'distanceMeters': 32000, 'durationSeconds': 2700, 'points': [
      {'lat': 48.869, 'lng': 2.331}, {'lat': 48.95, 'lng': 2.45}, {'lat': 49.009, 'lng': 2.547}]};
  }
  if (path.endsWith('/onboarding/status')) {
    return {'vehicles': [
      {'id': 'v1', 'status': 'APPROVED', 'category_id': 'cat', 'brand': 'Mercedes', 'model': 'Classe E', 'category_name': 'Confort', 'seats': 4, 'baggage_capacity': 4},
    ]};
  }
  if (path.endsWith('/quote')) return {'driverNetMinor': 4800, 'commissionRateBps': 800, 'commissionMinor': 384, 'customerTotalMinor': 5184};
  if (path.endsWith('/suggested-price')) return {'available': true, 'netLowMinor': 4500, 'netHighMinor': 6000};
  if (method == 'POST') return {'offerId': 'o1'};
  return _request;
}

Future<void> _settle(WidgetTester t) async {
  for (var j = 0; j < 8; j++) {
    await t.pump(const Duration(milliseconds: 150));
  }
}

Widget _app() => MaterialApp(theme: veyraTheme(), home: const RequestScreen(bookingId: 'b'), debugShowCheckedModeBanner: false);

void main() {
  setUpAll(loadAppFonts);
  testWidgets('request detail', (tester) async {
    fakeApi(_responses);
    await shot(tester, _app(), 'driver_04_request');
  });
  testWidgets('create offer', (tester) async {
    fakeApi(_responses);
    await shot(tester, _app(), 'driver_05_offer', before: (t) async {
      await t.tap(find.text('Créer mon offre'));
      await _settle(t);
      await t.enterText(find.byKey(const ValueKey('offer-amount')), '48,00');
      await _settle(t);
    });
  });
  testWidgets('offer summary', (tester) async {
    fakeApi(_responses);
    await shot(tester, _app(), 'driver_06_summary', before: (t) async {
      await t.tap(find.text('Créer mon offre'));
      await _settle(t);
      await t.enterText(find.byKey(const ValueKey('offer-amount')), '48,00');
      await _settle(t);
      await t.tap(find.text('Envoyer mon offre'));
      await _settle(t);
    });
  });
  testWidgets('offer sent', (tester) async {
    fakeApi(_responses);
    await shot(tester, _app(), 'driver_07_sent', before: (t) async {
      await t.tap(find.text('Créer mon offre'));
      await _settle(t);
      await t.enterText(find.byKey(const ValueKey('offer-amount')), '48,00');
      await _settle(t);
      await t.tap(find.text('Envoyer mon offre'));
      await _settle(t);
      await t.tap(find.text('Confirmer et envoyer'));
      await _settle(t);
    });
  });
}
