import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/main.dart';

void main() {
  testWidgets('profile failure preserves loaded identity and reports error',
      (tester) async {
    var updates = 0;
    api.dio.interceptors.clear();
    addTearDown(api.dio.interceptors.clear);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      if (request.method == 'PATCH') {
        updates++;
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
                  'id': 'account-user',
                  'first_name': 'Alex',
                  'last_name': 'Martin',
                  'phone': '+33612345678',
                  'kyc_status': 'SUBMITTED',
                }));
    }));
    await tester.pumpWidget(const MaterialApp(home: AccountScreen()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.text('Informations personnelles'), 200);
    await tester.tap(find.text('Informations personnelles'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Chris');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(updates, 1);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Alex Martin'), findsOneWidget);
    expect(find.text('Chris Martin'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
