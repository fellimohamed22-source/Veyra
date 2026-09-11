import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../../api.dart';

typedef DriverPositionHandler=void Function(Position position);
typedef DriverLocationErrorHandler=void Function(Object error);

class DriverLocationTracker {
  final Api api;
  final Duration minimumUploadInterval;
  final int distanceFilterMeters;

  StreamSubscription<Position>? _subscription;
  DateTime? _lastUploadAt;
  int _lastSequence=0;
  bool _uploading=false;
  bool _disposed=false;

  DriverLocationTracker({
    required this.api,
    this.minimumUploadInterval=const Duration(seconds:5),
    this.distanceFilterMeters=5,
  });

  bool get running=>_subscription!=null;

  Future<void> start({
    required String bookingId,
    required DriverPositionHandler onPosition,
    required DriverLocationErrorHandler onError,
  }) async {
    if(_disposed)return;
    await stop();

    if(!await Geolocator.isLocationServiceEnabled()){
      throw StateError('LOCATION_SERVICE_DISABLED');
    }

    var permission=await Geolocator.checkPermission();
    if(permission==LocationPermission.denied){
      permission=await Geolocator.requestPermission();
    }
    if(permission==LocationPermission.denied||
       permission==LocationPermission.deniedForever){
      throw StateError('LOCATION_PERMISSION_DENIED');
    }

    final initial=await Geolocator.getCurrentPosition(
      locationSettings:const LocationSettings(accuracy:LocationAccuracy.high),
    );
    onPosition(initial);
    await _upload(bookingId,initial,onError);

    _subscription=Geolocator.getPositionStream(
      locationSettings:LocationSettings(
        accuracy:LocationAccuracy.high,
        distanceFilter:distanceFilterMeters,
      ),
    ).listen(
      (position) async {
        if(_disposed)return;
        onPosition(position);
        final now=DateTime.now();
        if(_lastUploadAt!=null&&now.difference(_lastUploadAt!)<minimumUploadInterval){
          return;
        }
        await _upload(bookingId,position,onError);
      },
      onError:onError,
    );
  }

  Future<void> _upload(
    String bookingId,
    Position position,
    DriverLocationErrorHandler onError,
  ) async {
    if(_uploading||_disposed)return;
    _uploading=true;
    try{
      final epochSequence=DateTime.now().microsecondsSinceEpoch;
      final sequence=epochSequence<=_lastSequence?_lastSequence+1:epochSequence;
      _lastSequence=sequence;
      await api.updateLocation(
        bookingId:bookingId,
        lat:position.latitude,
        lng:position.longitude,
        sequenceNo:sequence,
        accuracyM:position.accuracy,
        heading:position.heading,
        speedMps:position.speed,
      );
      _lastUploadAt=DateTime.now();
    }catch(error){
      onError(error);
    }finally{
      _uploading=false;
    }
  }

  Future<void> stop() async {
    final subscription=_subscription;
    _subscription=null;
    if(subscription!=null){
      await subscription.cancel();
    }
  }

  Future<void> dispose() async {
    _disposed=true;
    await stop();
  }
}
