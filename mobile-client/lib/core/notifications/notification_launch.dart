import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local notifications need their own cold-start payload, separate from FCM.
Future<void> resumeNotificationLaunch(
  FlutterLocalNotificationsPlugin plugin,
  void Function(String payload) onTap,
) async {
  final launch = await plugin.getNotificationAppLaunchDetails();
  final payload = launch?.notificationResponse?.payload;
  if (launch?.didNotificationLaunchApp == true &&
      payload != null &&
      payload.isNotEmpty) {
    onTap(payload);
  }
}
