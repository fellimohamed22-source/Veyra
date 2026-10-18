import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/core/widgets/notifications_view.dart';

/// Board 16 / CL-18: grouped by day, unread dot, read on tap, read all.
void main() {
  testWidgets('notifications show read state and update the badge', (tester) async {
    final now = DateTime.now();
    var items = <Map<String, dynamic>>[
      {'id': 'n1', 'template_code': 'NEW_BOOKING', 'unread': true, 'created_at': now.toUtc().toIso8601String(),
        'data': '{"bookingId":"b1"}', 'pickup_address': 'Paris', 'dropoff_address': 'Orly'},
      {'id': 'n2', 'template_code': 'OFFER_ACCEPTED', 'unread': false, 'created_at': now.subtract(const Duration(days: 1)).toUtc().toIso8601String(), 'data': '{}'},
      {'id': 'n3', 'template_code': 'NEW_OFFER', 'unread': true, 'created_at': now.subtract(const Duration(days: 5)).toUtc().toIso8601String(), 'data': '{}'},
    ];
    final readIds = <String>[];
    var opened = '';
    var readAll = 0;
    veyraUnreadNotifications.value = 2;
    await tester.pumpWidget(MaterialApp(home: VeyraNotificationsScreen(
      load: () async => items,
      markRead: (id) async { readIds.add(id); return 1; },
      markAllRead: () async { readAll++; items = [for (final i in items) {...i, 'unread': false}]; return 0; },
      open: (n) => opened = n.bookingId ?? '',
    )));
    await tester.pumpAndSettle();

    expect(find.text('Aujourd’hui'), findsOneWidget);
    expect(find.text('Hier'), findsOneWidget);
    expect(find.text('Plus anciennes'), findsOneWidget);
    expect(find.byKey(const ValueKey('unread-dot')), findsNWidgets(2));

    await tester.tap(find.text('Nouvelle demande disponible'));
    await tester.pumpAndSettle();
    expect(readIds, ['n1']);
    expect(opened, 'b1');
    expect(veyraUnreadNotifications.value, 1);
    expect(find.byKey(const ValueKey('unread-dot')), findsOneWidget);

    await tester.tap(find.text('Tout marquer comme lu'));
    await tester.pumpAndSettle();
    expect(readAll, 1);
    expect(veyraUnreadNotifications.value, 0);
    expect(find.byKey(const ValueKey('unread-dot')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
