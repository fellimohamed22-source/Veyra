import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/main.dart';
import 'package:veyra_driver/core/widgets/state_views.dart';

void main() {
  tearDown(api.dio.interceptors.clear);
  for (final screen in <Widget>[
    const OpportunitiesScreen(),
    const AgendaScreen(),
    const DriverNotificationsScreen()
  ]) {
    testWidgets(
        '${screen.runtimeType} keeps failed refresh visible and retryable',
        (tester) async {
      var offline = true;
      var requests = 0;
      api.dio.interceptors.clear();
      api.dio.interceptors
          .add(InterceptorsWrapper(onRequest: (request, handler) {
        requests++;
        if (offline) {
          handler.reject(DioException(
              requestOptions: request, type: DioExceptionType.connectionError));
        } else {
          handler.resolve(Response(
              requestOptions: request,
              statusCode: 200,
              data: request.path == '/api/v1/me'
                  ? <String, dynamic>{}
                  : <dynamic>[]));
        }
      }));
      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();
      final refresh =
          tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
      final before = requests;
      await expectLater(refresh.onRefresh(), completes);
      await tester.pumpAndSettle();
      expect(requests, greaterThan(before));
      expect(find.byType(VeyraOfflineBanner), findsWidgets);
      expect(tester.takeException(), isNull);
      offline = false;
      await refresh.onRefresh();
      await tester.pumpAndSettle();
      expect(find.byType(VeyraOfflineBanner), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
