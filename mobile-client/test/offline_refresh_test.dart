import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/main.dart';
import 'package:veyra_client/core/widgets/state_views.dart';

void main() {
  tearDown(api.dio.interceptors.clear);
  for (final screen in <Widget>[
    const HomeScreen(),
    const AccueilScreen(),
    const NotificationsScreen()
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
      final failedRefresh = refresh.onRefresh();
      await tester.pumpAndSettle();
      await expectLater(failedRefresh, completes);
      expect(requests, greaterThan(before));
      expect(find.byType(VeyraOfflineBanner), findsWidgets);
      expect(tester.takeException(), isNull);
      offline = false;
      final recovery = refresh.onRefresh();
      await tester.pumpAndSettle();
      await expectLater(recovery, completes);
      expect(find.byType(VeyraOfflineBanner), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
