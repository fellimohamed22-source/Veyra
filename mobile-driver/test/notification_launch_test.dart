import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/core/notifications/notification_launch.dart';

class LaunchPlugin extends Fake implements FlutterLocalNotificationsPlugin {
  NotificationAppLaunchDetails? launch;
  @override
  Future<NotificationAppLaunchDetails?>
      getNotificationAppLaunchDetails() async => launch;
}

void main() {
  test('cold launch forwards notification payload; normal launch does not',
      () async {
    final plugin = LaunchPlugin();
    final opened = <String>[];
    await resumeNotificationLaunch(plugin, opened.add);
    expect(opened, isEmpty);
    plugin.launch = const NotificationAppLaunchDetails(false,
        notificationResponse: NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            payload: 'stale'));
    await resumeNotificationLaunch(plugin, opened.add);
    expect(opened, isEmpty);
    plugin.launch = const NotificationAppLaunchDetails(true,
        notificationResponse: NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            payload: '{"bookingId":"ride-1"}'));
    await resumeNotificationLaunch(plugin, opened.add);
    expect(opened, ['{"bookingId":"ride-1"}']);
  });
}
