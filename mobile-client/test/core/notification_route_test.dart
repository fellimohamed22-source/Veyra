import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/core/notification_route.dart';

void main(){
  test('offer notifications open the offers, status updates open the booking',(){
    expect(notificationRoute({'bookingId':'b1','templateCode':'NEW_OFFER'}),'/offers/b1');
    expect(notificationRoute({'booking_id':'b1','template_code':'NEW_OFFER'}),'/offers/b1');
    expect(notificationRoute({'bookingId':'b1','event':'booking.status.driver_arrived'}),'/booking/b1');
  });
  test('missing targets are ignored and identifiers cannot inject a route',(){
    expect(notificationRoute({}),isNull);
    expect(notificationRoute({'bookingId':' '}),isNull);
    expect(notificationRoute({'bookingId':'b/other?x=1'}),'/booking/b%2Fother%3Fx%3D1');
  });
}
