import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/main.dart';
import 'package:veyra_client/app/theme.dart';
import 'harness.dart';

void main() {
  setUpAll(loadAppFonts);
  testWidgets('chat', (tester) async {
    final now = DateTime.now().toUtc();
    String at(int minutesAgo) => now.subtract(Duration(minutes: minutesAgo)).toIso8601String();
    fakeApi((path, method, data) {
      if (path.endsWith('/me')) return {'id': 'me'};
      if (path.endsWith('/messages')) {
        return [
          {'id': '1', 'senderUserId': 'd', 'body': 'Bonjour, je suis en route, j’arrive dans 10 minutes.', 'sentAt': at(60 * 24 + 5)},
          {'id': '2', 'senderUserId': 'me', 'body': 'Parfait, merci !', 'sentAt': at(60 * 24 + 3)},
          {'id': '3', 'senderUserId': 'd', 'body': 'Je suis devant l’hôtel, Mercedes noire.', 'sentAt': at(4)},
          {'id': '4', 'senderUserId': 'me', 'body': 'Je descends tout de suite.', 'sentAt': at(2)},
        ];
      }
      return {'id': 'b1', 'status': 'DRIVER_ARRIVED', 'driver_name': 'Thomas Martin', 'pickup_address': 'Vieux-Port, Marseille', 'dropoff_address': 'Aéroport Marseille Provence, Marignane'};
    });
    await shot(tester, MaterialApp(theme: veyraTheme(), debugShowCheckedModeBanner: false, home: const ChatScreen(bookingId: 'b1')), 'chat_01');
  });
}
