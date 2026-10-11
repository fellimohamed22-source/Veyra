import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:veyra_driver/main.dart';

void main() {
  testWidgets(
      'approved driver can open professional and vehicle details from account',
      (tester) async {
    api.dio.interceptors.clear();
    addTearDown(api.dio.interceptors.clear);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      if (request.path.endsWith('/avatar')) {
        handler.reject(DioException(
            requestOptions: request,
            response: Response(requestOptions: request, statusCode: 404)));
        return;
      }
      handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: request.path.endsWith('/documents')
              ? <dynamic>[]
              : request.path.endsWith('/vehicle-categories')
                  ? [
                      {
                        'id': 'category-1',
                        'display_name': 'Standard',
                        'capacity': 4
                      }
                    ]
                  : request.path.endsWith('/status')
                      ? {
                          'status': 'ACTIVE',
                          'kyc_status': 'APPROVED',
                          'marketplace_enabled': true,
                          'documents': <dynamic>[],
                          'vehicles': [
                            {
                              'id': 'vehicle-1',
                              'category_id': 'category-1',
                              'brand': 'Mercedes',
                              'model': 'Classe E',
                              'plate_number': 'AA-123-BB',
                              'color': 'Noir',
                              'year': 2024,
                              'status': 'APPROVED',
                              'category_name': 'Standard'
                            }
                          ],
                          'company': [
                            {
                              'legal_name': 'VTC Martin',
                              'siren': '123456789',
                              'siret': '12345678900001'
                            }
                          ],
                          'registration': [
                            {
                              'registration_number': 'VTC-1',
                              'card_number': 'CARD-1'
                            }
                          ],
                        }
                      : {
                          'first_name': 'Alex',
                          'last_name': 'Martin',
                          'phone': '+33612345678'
                        }));
    }));
    final router = GoRouter(initialLocation: '/account', routes: [
      GoRoute(path: '/account', builder: (_, __) => const AccountScreen()),
      GoRoute(path: '/kyc', builder: (_, __) => const KycScreen())
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Dossier approuvé'), 200);
    await tester.tap(find.text('Dossier approuvé'));
    await tester.pumpAndSettle();
    expect(find.byType(KycScreen), findsOneWidget);
    expect(find.textContaining('AA-123-BB'), findsWidgets);
    expect(find.text('VTC Martin'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
