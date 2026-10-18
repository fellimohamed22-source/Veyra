import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/main.dart';
import 'package:veyra_client/app/theme.dart';

void main() {
  for(final fee in [0, 500]) {
    testWidgets('cancellation fee $fee requires a valid preview and refreshes status', (tester) async {
      var previewOffline = true;
      var status = 'CONFIRMED';
      var cancellations = 0;
      RequestOptions? cancelRequest;
      RequestInterceptorHandler? cancelHandler;
      api.dio.interceptors.clear();
      addTearDown(api.dio.interceptors.clear);
      api.dio.interceptors.add(InterceptorsWrapper(onRequest:(request,handler){
        if(request.path.endsWith('/cancellation-preview')) {
          if(previewOffline) {
            handler.reject(DioException(requestOptions:request,type:DioExceptionType.connectionError));
          } else {
            handler.resolve(Response(requestOptions:request,statusCode:200,
                data:{'free':fee==0,'cancellationFeeMinor':fee}));
          }
        } else if(request.method=='POST') {
          cancellations++;
          cancelRequest=request;
          cancelHandler=handler;
        } else {
          handler.resolve(Response(requestOptions:request,statusCode:200,data:{
            'status':status,'payment_method':'CASH','pickup_address':'Nice',
            'dropoff_address':'Cannes','scheduled_at':'2026-10-12T12:00:00Z'}));
        }
      }));
      await tester.pumpWidget(MaterialApp(theme:veyraTheme(),
          home:const BookingDetailScreen(bookingId:'ride-1')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Annuler la réservation'),180,
          scrollable:find.byType(Scrollable).first);
      await tester.tap(find.text('Annuler la réservation'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'Confirmer l’annulation')).onPressed,isNull);
      expect(cancellations,0);
      await tester.tap(find.text('Garder la réservation'));
      await tester.pumpAndSettle();
      previewOffline=false;
      await tester.tap(find.text('Annuler la réservation'));
      await tester.pumpAndSettle();
      expect(find.textContaining(fee==0?'0,00 €':'5,00 €'),findsOneWidget);
      await tester.tap(find.text('Confirmer l’annulation'));
      await tester.pumpAndSettle();
      expect(cancellations,1);
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'Annulation…')).onPressed,isNull);
      status='CANCELLED';
      cancelHandler!.resolve(Response(requestOptions:cancelRequest!,statusCode:200,
          data:{'cancellationFeeMinor':fee}));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Annulée'),-180,
          scrollable:find.byType(Scrollable).first);
      expect(find.text('Annulée'),findsOneWidget);
      expect(cancellations,1);
      await tester.scrollUntilVisible(find.text('Réserver à nouveau'),180,
          scrollable:find.byType(Scrollable).first);
      expect(find.text('Annuler la réservation'),findsNothing);
      expect(tester.takeException(),isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
