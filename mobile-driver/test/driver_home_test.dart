import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/main.dart';
import 'package:veyra_driver/app/theme.dart';
import 'package:veyra_driver/ui/driver_home_screen.dart';

void main() {
  testWidgets('driver home shows counters, next ride and toggles availability (DR-01)', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var accepting = true;
    final puts = <bool>[];
    final pushed = <String>[];
    api.dio.interceptors.clear();
    addTearDown(api.dio.interceptors.clear);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      if (r.path.endsWith('/availability') && r.method == 'PUT') {
        accepting = (r.data as Map)['acceptingRequests'] as bool;
        puts.add(accepting);
        return h.resolve(Response(requestOptions: r, statusCode: 200, data: {'acceptingRequests': accepting}));
      }
      if (r.path.endsWith('/dashboard')) {
        return h.resolve(Response(requestOptions: r, statusCode: 200, data: {
          'acceptingRequests': accepting, 'availableRequests': 5, 'pendingOffers': 2, 'upcomingRides': 1,
          'nextRide': {'id': 'ride-1', 'status': 'CONFIRMED', 'scheduled_at': DateTime.now().add(const Duration(hours: 2, minutes: 5)).toUtc().toIso8601String(),
            'pickup_address': 'Paris, 8e arrondissement', 'dropoff_address': 'Aéroport CDG (Terminal 2E)', 'passenger_count': 2, 'baggage_count': 3},
        }));
      }
      h.resolve(Response(requestOptions: r, statusCode: 200, data: accepting ? [
        {'id': 'b-1', 'scheduled_at': DateTime.now().add(const Duration(hours: 5)).toUtc().toIso8601String(), 'pickup_address': 'Paris, 16e',
          'dropoff_address': 'Aéroport d’Orly (ORY)', 'passenger_count': 3, 'baggage_count': 2, 'customer_favorite': true, 'best_other_offer_minor': 4800},
      ] : []));
    }));
    await tester.pumpWidget(MaterialApp(theme: veyraTheme(), home: DriverHomeScreen(api: api, go: pushed.add, push: pushed.add)));
    await tester.pumpAndSettle();

    expect(find.text('Disponible pour recevoir des demandes'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('Offres en attente'), findsOneWidget);
    expect(find.text('Dans 2 h'), findsOneWidget);
    expect(find.text('Client préféré'), findsOneWidget);
    expect(find.text('48,00 €'), findsOneWidget);

    await tester.tap(find.text('Voir les détails'));
    expect(pushed.last, '/ride/ride-1');

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(puts, [false]);
    expect(find.text('Hors ligne'), findsOneWidget);
    expect(find.text('Passez en ligne pour recevoir de nouvelles demandes.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
