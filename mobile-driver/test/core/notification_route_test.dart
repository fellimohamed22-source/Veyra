import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/core/notification_route.dart';

void main(){
  test('new requests and assigned rides have distinct destinations',(){
    expect(notificationRoute({'bookingId':'b1','templateCode':'NEW_BOOKING'}),'/request/b1');
    expect(notificationRoute({'booking_id':'b1','template_code':'NEW_BOOKING'}),'/request/b1');
    expect(notificationRoute({'bookingId':'b1','templateCode':'OFFER_ACCEPTED'}),'/ride/b1');
  });
  test('missing targets are ignored',(){
    expect(notificationRoute({}),isNull);
    expect(notificationRoute({'bookingId':''}),isNull);
  });
}
