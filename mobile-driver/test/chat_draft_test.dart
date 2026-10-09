import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/main.dart';

void main() {
  testWidgets('failed chat send keeps draft for a successful retry',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    var attempts = 0;
    api.dio.interceptors.clear();
    addTearDown(api.dio.interceptors.clear);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      if (request.method == 'POST') {
        attempts++;
        if (attempts == 1) {
          handler.reject(DioException(
              requestOptions: request, type: DioExceptionType.connectionError));
          return;
        }
        handler.resolve(Response(
            requestOptions: request,
            statusCode: 200,
            data: {
              'id': 'message-1',
              'body': request.data['body'],
              'sender_user_id': 'me'
            }));
        return;
      }
      handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data:
              request.path.endsWith('messages') ? <dynamic>[] : {'id': 'me'}));
    }));
    await tester
        .pumpWidget(const MaterialApp(home: DriverChatScreen(bookingId: 'ride-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Je suis devant la gare');
    await tester.tap(find.byTooltip('Envoyer'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Je suis devant la gare');
    expect(attempts, 1);
    await tester.tap(find.byTooltip('Envoyer'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    expect(attempts, 2);
    expect(find.text('Je suis devant la gare'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

