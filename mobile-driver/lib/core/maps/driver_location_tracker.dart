import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../../api.dart';

typedef DriverPositionHandler = void Function(Position position);
typedef DriverLocationErrorHandler = void Function(Object error);
typedef DriverLocationUploadErrorHandler = void Function(Object error);
typedef DriverLocationUploadSuccessHandler = void Function();

/// One active ride owns location sharing; screens only attach listeners.
class DriverLocationTracker {
  final Api api;
  final Duration minimumUploadInterval;
  final int distanceFilterMeters;
  final Future<void> Function()? prepareLocation;
  final Stream<Position> Function(LocationSettings)? positionStream;
  StreamSubscription<Position>? _subscription;
  Timer? _statusTimer;
  DateTime? _lastUploadAt;
  int _lastSequence = 0;
  int _generation = 0;
  bool _uploading = false, _disposed = false, _checking = false;
  String? bookingId;
  Object? _owner;
  Position? _position;
  DriverPositionHandler? _onPosition;
  DriverLocationErrorHandler? _onError, _onUploadError;
  DriverLocationUploadSuccessHandler? _onUploadSuccess;

  DriverLocationTracker(
      {required this.api,
      this.minimumUploadInterval = const Duration(seconds: 5),
      this.distanceFilterMeters = 5,
      this.prepareLocation,
      this.positionStream});
  bool get running => _subscription != null;

  void detach(Object owner) {
    if (!identical(owner, _owner)) return;
    _owner = null;
    _onPosition = null;
    _onError = null;
    _onUploadError = null;
    _onUploadSuccess = null;
  }

  Future<void> start(
      {required String bookingId,
      required DriverPositionHandler onPosition,
      required DriverLocationErrorHandler onError,
      DriverLocationUploadErrorHandler? onUploadError,
      DriverLocationUploadSuccessHandler? onUploadSuccess,
      Object? owner}) async {
    if (_disposed) return;
    if (!running || this.bookingId != bookingId) {
      await stop();
      final generation = ++_generation;
      if (prepareLocation != null) {
        await prepareLocation!();
      } else {
        if (!await Geolocator.isLocationServiceEnabled())
          throw StateError('LOCATION_SERVICE_DISABLED');
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied)
          permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever)
          throw StateError('LOCATION_PERMISSION_DENIED');
      }
      if (_disposed || generation != _generation) return;
      this.bookingId = bookingId;
      final LocationSettings settings = defaultTargetPlatform ==
              TargetPlatform.android
          ? AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: distanceFilterMeters,
              intervalDuration: minimumUploadInterval,
              foregroundNotificationConfig: const ForegroundNotificationConfig(
                  notificationTitle: 'Course Veyra en cours',
                  notificationText:
                      'Votre position est partagée avec le client pendant la course.',
                  enableWakeLock: true,
                  setOngoing: true))
          : LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: distanceFilterMeters);
      _subscription = (positionStream?.call(settings) ??
              Geolocator.getPositionStream(locationSettings: settings))
          .listen((p) {
        if (_disposed || generation != _generation) return;
        _position = p;
        _onPosition?.call(p);
        if (_lastUploadAt == null ||
            DateTime.now().difference(_lastUploadAt!) >= minimumUploadInterval)
          unawaited(_upload(bookingId, p, generation));
      }, onError: (Object error) {
        _onError?.call(error);
      });
      _statusTimer =
          Timer.periodic(const Duration(seconds: 15), (_) => verifyBooking());
    }
    _owner = owner;
    _onPosition = onPosition;
    _onError = onError;
    _onUploadError = onUploadError ?? onError;
    _onUploadSuccess = onUploadSuccess;
    final p = _position;
    if (p != null &&
        DateTime.now().difference(p.timestamp) < const Duration(seconds: 30))
      onPosition(p);
  }

  Future<void> verifyBooking() async {
    final id = bookingId;
    if (id == null || _checking) return;
    _checking = true;
    try {
      final booking = await api.bookingDetail(id);
      if (bookingId == id &&
          !{'DRIVER_EN_ROUTE', 'DRIVER_ARRIVED', 'IN_PROGRESS'}
              .contains(booking['status'])) await stop();
    } on DioException catch (e) {
      if (bookingId == id && {401, 403, 404}.contains(e.response?.statusCode))
        await stop();
    } catch (_) {
      // A network interruption must not stop an active ride's location stream.
    } finally {
      _checking = false;
    }
  }

  Future<void> _upload(String id, Position position, int generation) async {
    if (_uploading || _disposed || generation != _generation) return;
    _uploading = true;
    try {
      final sequence = DateTime.now().microsecondsSinceEpoch;
      _lastSequence = sequence <= _lastSequence ? _lastSequence + 1 : sequence;
      await api.updateLocation(
          bookingId: id,
          lat: position.latitude,
          lng: position.longitude,
          sequenceNo: _lastSequence,
          accuracyM: position.accuracy,
          heading: position.heading,
          speedMps: position.speed);
      if (generation == _generation) {
        _lastUploadAt = DateTime.now();
        _onUploadSuccess?.call();
      }
    } catch (error) {
      if (generation == _generation) {
        _onUploadError?.call(error);
        if (error is DioException &&
            {401, 403, 404}.contains(error.response?.statusCode)) await stop();
      }
    } finally {
      _uploading = false;
    }
  }

  Future<void> stop() async {
    _generation++;
    _statusTimer?.cancel();
    _statusTimer = null;
    final subscription = _subscription;
    _subscription = null;
    bookingId = null;
    _position = null;
    _lastUploadAt = null;
    _owner = null;
    _onPosition = null;
    _onError = null;
    _onUploadError = null;
    _onUploadSuccess = null;
    await subscription?.cancel();
  }

  Future<void> dispose() async {
    _disposed = true;
    await stop();
  }
}
