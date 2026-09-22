import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/main.dart';
import 'package:veyra_client/core/formatters/status_labels.dart';

void main(){
  test('outbox arrival event opens the correct live booking',(){
    expect(clientNotificationRoute('ride-1','BOOKING_STATUS',{'event':'booking.status.driver_arrived'}),'/live/ride-1');
    expect(clientNotificationRoute('ride-1','BOOKING_STATUS',{'event':'booking.status.completed'}),'/booking/ride-1');
    expect(clientNotificationRoute('ride-1','NEW_OFFER',{}),'/offers/ride-1');
    expect(clientNotificationRoute('ride-1','PAYMENT_REQUIRED',{}),'/payment/ride-1');
  });
  test('actual driver cancellation code is translated',(){
    expect(VeyraStatusLabels.bookingStatus('DRIVER_CANCELLED'),'Annulée par le chauffeur');
  });
  test('pending payment is never presented as paid',(){
    expect(paymentStatusLabel('CAPTURED'),'Payé');
    expect(paymentStatusLabel('PENDING'),'En cours de confirmation');
    expect(paymentStatusLabel(null),'À payer');
  });
}
