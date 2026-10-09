import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/core/maps/tracking_eta.dart';

void main() {
  test('ETA requires fresh GPS, an active ride and its actual target', () {
    final now = DateTime.utc(2026, 10, 9, 12);
    final booking = <String, dynamic>{
      'status': 'DRIVER_EN_ROUTE',
      'pickup_lat': 48.8,
      'pickup_lng': 2.3,
    };
    final location = <String, dynamic>{
      'available': true,
      'lat': 48.7,
      'lng': 2.2,
      'recorded_at': now.toIso8601String(),
    };
    expect(canEstimateTrackingEta(booking, location, now), isTrue);
    expect(
        canEstimateTrackingEta(booking, {...location, 'available': false}, now),
        isFalse);
    expect(
        canEstimateTrackingEta(
            booking, {...location, 'recorded_at': null}, now),
        isFalse);
    expect(
        canEstimateTrackingEta(
            booking, location, now.add(const Duration(minutes: 3))),
        isFalse);
    for (final status in [
      'COMPLETED',
      'CANCELLED',
      'CONFIRMED',
      'IN_PROGRESS'
    ]) {
      expect(
          canEstimateTrackingEta({...booking, 'status': status}, location, now),
          isFalse);
    }
    expect(
        canEstimateTrackingEta({
          ...booking,
          'status': 'IN_PROGRESS',
          'dropoff_lat': 48.9,
          'dropoff_lng': 2.4
        }, location, now),
        isTrue);
  });
}
