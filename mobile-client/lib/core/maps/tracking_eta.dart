bool canEstimateTrackingEta(Map<String, dynamic>? booking,
    Map<String, dynamic>? location, DateTime now) {
  if (booking == null || location?['available'] != true) return false;
  if (!{'DRIVER_EN_ROUTE', 'DRIVER_ARRIVED', 'IN_PROGRESS'}
      .contains(booking['status'])) return false;
  final recorded =
      DateTime.tryParse(location?['recorded_at']?.toString() ?? '');
  if (recorded == null ||
      now.difference(recorded) > const Duration(minutes: 2)) {
    return false;
  }
  final prefix = booking['status'] == 'IN_PROGRESS' ? 'dropoff' : 'pickup';
  return location?['lat'] is num &&
      location?['lng'] is num &&
      booking['${prefix}_lat'] is num &&
      booking['${prefix}_lng'] is num;
}
