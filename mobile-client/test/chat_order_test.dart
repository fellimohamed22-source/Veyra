import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/main.dart';

/// The newest message is at the bottom, including one just sent whose
/// server answer carries no timestamp.
void main() {
  testWidgets('newest message at the bottom', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'accessToken': 't', 'refreshToken': 'r'});
    final old = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
    api.dio.interceptors.clear();
    addTearDown(api.dio.interceptors.clear);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      Object? data;
      if (r.path.endsWith('/me')) {
        data = {'id': 'me'};
      } else if (r.path.endsWith('/messages') && r.method == 'POST') {
        data = {'id': 'm3', 'senderUserId': 'me', 'body': 'Message récent'};
      } else if (r.path.endsWith('/messages')) {
        data = [
          {'id': 'm1', 'sender_user_id': 'd', 'body': 'Premier message', 'sent_at': old.toIso8601String()},
          {'id': 'm2', 'sender_user_id': 'me', 'body': 'Deuxième message', 'sent_at': old.add(const Duration(minutes: 1)).toIso8601String()},
        ];
      } else {
        data = {'id': 'b1', 'status': 'CONFIRMED', 'driver_name': 'Thomas', 'pickup_address': 'A', 'dropoff_address': 'B'};
      }
      h.resolve(Response(requestOptions: r, statusCode: 200, data: data));
    }));
    await tester.pumpWidget(const MaterialApp(home: ChatScreen(bookingId: 'b1')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getTopLeft(find.text('Deuxième message')).dy, greaterThan(tester.getTopLeft(find.text('Premier message')).dy));
    await tester.enterText(find.byKey(const ValueKey('chat-input')), 'Message récent');
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getTopLeft(find.text('Message récent')).dy, greaterThan(tester.getTopLeft(find.text('Deuxième message')).dy));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
