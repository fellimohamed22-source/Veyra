/// Only a trip already under way should replace the home screen on restart.
String? activeBookingId(List<dynamic> bookings) {
  for (final status in ['IN_PROGRESS', 'DRIVER_ARRIVED', 'DRIVER_EN_ROUTE']) {
    for (final booking in bookings.whereType<Map>()) {
      final id = booking['id']?.toString();
      if (booking['status'] == status && id != null && id.isNotEmpty) return id;
    }
  }
  return null;
}
