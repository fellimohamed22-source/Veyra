import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/main.dart';

void main() {
  testWidgets('saved vehicle in a retired category does not crash onboarding',
      (tester) async {
    api.dio.interceptors.clear();
    addTearDown(api.dio.interceptors.clear);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: request.path.endsWith('vehicle-categories')
              ? [
                  {'id': 'new-category', 'display_name': 'Berline'}
                ]
              : {
                  'kyc_status': 'APPROVED',
                  'marketplace_enabled': true,
                  'vehicles': [
                    {
                      'category_id': 'retired-category',
                      'brand': 'Mercedes',
                      'model': 'Classe E',
                      'plate_number': 'AB-123-CD',
                      'year': 2024,
                      'status': 'PENDING'
                    }
                  ]
                }));
    }));
    await tester.pumpWidget(const MaterialApp(home: KycScreen()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Catégorie'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(tester.takeException(), isNull);
    expect(find.text('Accéder aux demandes'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
