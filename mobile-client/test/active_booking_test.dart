import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/core/active_booking.dart';

void main() {
  test('restart selects a real active trip, not a future or completed trip',
      () {
    expect(
        activeBookingId([
          {'id': 'future', 'status': 'CONFIRMED'},
          {'id': 'past', 'status': 'COMPLETED'},
          {'id': 'active', 'status': 'IN_PROGRESS'}
        ]),
        'active');
    expect(
        activeBookingId([
          {'id': 'future', 'status': 'CONFIRMED'},
          {'id': 'cancelled', 'status': 'CANCELLED'}
        ]),
        isNull);
    expect(
        activeBookingId([
          {'status': 'IN_PROGRESS'},
          {'id': 'approach', 'status': 'DRIVER_EN_ROUTE'}
        ]),
        'approach');
    expect(activeBookingId([]), isNull);
  });
}
