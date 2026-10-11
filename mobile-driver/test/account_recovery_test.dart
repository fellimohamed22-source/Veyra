import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/main.dart';
import 'package:veyra_driver/core/widgets/state_views.dart';

void main() {
  testWidgets('account initially offline can retry and load identity',
      (tester) async {
    var offline = true;
    api.dio.interceptors.clear();
    addTearDown(api.dio.interceptors.clear);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      if (offline) {
        handler.reject(DioException(
            requestOptions: request, type: DioExceptionType.connectionError));
        return;
      }
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
              : {
                  'first_name': 'Alex',
                  'last_name': 'Martin',
                  'phone': '+33612345678',
                  'kyc_status': 'SUBMITTED'
                }));
    }));
    await tester.pumpWidget(const MaterialApp(home: AccountScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(VeyraErrorView), findsOneWidget);
    expect(tester.takeException(), isNull);
    offline = false;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('Alex Martin'), findsOneWidget);
    expect(find.byType(VeyraErrorView), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
