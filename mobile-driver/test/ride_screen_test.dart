import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/main.dart';
import 'package:veyra_driver/app/theme.dart';

/// Board 12 P7: confirmed ride detail with client card and actions.
void main() {
  Map<String, dynamic> ride(String status) => {
        'id': 'ride-1', 'status': status, 'payment_method': 'CASH',
        'pickup_address': 'Paris, 16e arrondissement, Rue de la Paix', 'dropoff_address': 'Aéroport d’Orly (ORY), Terminal 4',
        'pickup_lat': 48.86, 'pickup_lng': 2.28, 'dropoff_lat': 48.72, 'dropoff_lng': 2.36,
        'scheduled_at': DateTime.now().add(const Duration(hours: 2, minutes: 10)).toUtc().toIso8601String(),
        'customer_name': 'Sophie M.', 'passenger_count': 3, 'baggage_count': 2, 'category_name': 'Berline',
        'vehicle_brand': 'Mercedes', 'vehicle_model': 'Classe E', 'plate_number': 'AB-123-CD',
        'customer_notes': 'Deux valises et un siège enfant.',
        'customer_total_amount_minor': 5200, 'driver_net_amount_minor': 4800, 'platform_commission_amount_minor': 400,
      };

  Future<void> pump(WidgetTester tester, String status) async {
    tester.view.physicalSize = const Size(400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    api.dio.interceptors.clear();
    addTearDown(api.dio.interceptors.clear);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      h.resolve(Response(requestOptions: r, statusCode: 200,
          data: r.path.endsWith('/estimate') ? {'distanceMeters': 18000, 'durationSeconds': 1500} : ride(status)));
    }));
    await tester.pumpWidget(MaterialApp(theme: veyraTheme(), home: const RideScreen(bookingId: 'ride-1')));
    await tester.pumpAndSettle();
  }

  testWidgets('confirmed ride shows the client card, trip and cash amounts', (tester) async {
    await pump(tester, 'CONFIRMED');
    expect(find.text('Confirmée'), findsOneWidget);
    expect(find.text('Sophie M.'), findsOneWidget);
    expect(find.text('Dans 2 h'), findsOneWidget);
    expect(find.text('Paris'), findsOneWidget);
    expect(find.text('Deux valises et un siège enfant.'), findsOneWidget);
    expect(find.text('52,00 €'), findsOneWidget);
    expect(find.text('Je suis en route'), findsOneWidget);
    // Masked calls only (CL-15): the call button stays disabled.
    final call = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.phone_outlined));
    expect(call.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed ride asks to rate the client', (tester) async {
    await pump(tester, 'COMPLETED');
    expect(find.text('Terminée'), findsOneWidget);
    expect(find.text('Noter le client'), findsOneWidget);
    expect(find.text('Je suis en route'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
