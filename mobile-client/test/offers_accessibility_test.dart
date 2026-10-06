import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/main.dart';

void main() {
  testWidgets('offer card fits enlarged text and requires confirmation',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var submissions = 0;
    api.dio.interceptors.clear();
    addTearDown(api.dio.interceptors.clear);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      if (request.method == 'POST') submissions++;
      handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: request.path.endsWith('/offers')
              ? [
                  {
                    'offerId': 'offer-1',
                    'driverFirstName': 'Alexandre',
                    'driverLastName': 'Martin',
                    'vehicleBrand': 'Mercedes',
                    'vehicleModel': 'Classe E',
                    'vehicleCategory': 'Berline',
                    'vehicleColor': 'Noir',
                    'vehicleYear': 2024,
                    'rating': 4.9,
                    'totalMinor': 123456,
                    'driverVerified': true
                  }
                ]
              : {
                  'pickup_address': 'Nice',
                  'dropoff_address': 'Cannes',
                  'scheduled_at': '2026-10-10T12:00:00Z',
                  'status': 'OFFERS_RECEIVED'
                }));
    }));
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!),
        home: const OffersScreen(bookingId: 'booking-1')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Alexandre'));
    await tester.tap(find.text('Alexandre'));
    await tester.pumpAndSettle();
    expect(find.text('Choisir ce chauffeur ?'), findsOneWidget);
    expect(submissions, 0);
    await tester.tap(find.text('Comparer encore'));
    await tester.pumpAndSettle();
    expect(submissions, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
