import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:veyra_driver/api.dart';
import 'package:veyra_driver/core/maps/driver_location_tracker.dart';

class TrackingApi extends Api {
  TrackingApi() : super('http://localhost');
  int uploads = 0;
  String status = 'DRIVER_EN_ROUTE';
  bool offline = false;
  @override
  Future<Map<String, dynamic>> bookingDetail(String id) async {
    if (offline)
      throw DioException(
          requestOptions: RequestOptions(path: id),
          type: DioExceptionType.connectionError);
    return {'status': status};
  }

  @override
  Future<void> updateLocation(
      {required String bookingId,
      required double lat,
      required double lng,
      required int sequenceNo,
      double? accuracyM,
      double? heading,
      double? speedMps}) async {
    uploads++;
  }
}

Position position() => Position(
    longitude: 6,
    latitude: 43,
    timestamp: DateTime.now(),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0);

void main() {
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  test('leaving and reopening a ride retains one stream and continues uploads',
      () async {
    final api = TrackingApi(), stream = StreamController<Position>.broadcast();
    var subscriptions = 0, notifications = 0;
    final owner = Object();
    final tracker = DriverLocationTracker(
        api: api,
        minimumUploadInterval: Duration.zero,
        prepareLocation: () async {},
        positionStream: (settings) {
          subscriptions++;
          expect(settings, isA<AndroidSettings>());
          expect((settings as AndroidSettings).foregroundNotificationConfig,
              isNotNull);
          return stream.stream;
        });
    await tracker.start(
        bookingId: 'ride',
        owner: owner,
        onPosition: (_) => notifications++,
        onError: (_) {});
    stream.add(position());
    await Future<void>.delayed(Duration.zero);
    tracker.detach(owner);
    stream.add(position());
    await Future<void>.delayed(Duration.zero);
    expect(api.uploads, 2);
    expect(notifications, 1);
    expect(tracker.running, isTrue);
    await tracker.start(
        bookingId: 'ride',
        owner: Object(),
        onPosition: (_) {},
        onError: (_) {});
    expect(subscriptions, 1);
    await tracker.dispose();
    await stream.close();
  });
  test('offline verification preserves tracking; remote cancellation stops it',
      () async {
    final api = TrackingApi(), stream = StreamController<Position>.broadcast();
    final tracker = DriverLocationTracker(
        api: api,
        prepareLocation: () async {},
        positionStream: (_) => stream.stream);
    await tracker.start(bookingId: 'ride', onPosition: (_) {}, onError: (_) {});
    api.offline = true;
    await tracker.verifyBooking();
    expect(tracker.running, isTrue);
    api.offline = false;
    api.status = 'CANCELLED';
    await tracker.verifyBooking();
    expect(tracker.running, isFalse);
    stream.add(position());
    await Future<void>.delayed(Duration.zero);
    expect(api.uploads, 0);
    await tracker.dispose();
    await stream.close();
  });
  test('logout during the permission request prevents a late stream start',
      () async {
    final gate = Completer<void>();
    var subscribed = false;
    final tracker = DriverLocationTracker(
        api: TrackingApi(),
        prepareLocation: () => gate.future,
        positionStream: (_) {
          subscribed = true;
          return const Stream.empty();
        });
    final starting =
        tracker.start(bookingId: 'ride', onPosition: (_) {}, onError: (_) {});
    await Future<void>.delayed(Duration.zero);
    await tracker.stop();
    gate.complete();
    await starting;
    expect(subscribed, isFalse);
    expect(tracker.running, isFalse);
    await tracker.dispose();
  });
}
