import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/main.dart';

void main(){
  setUp(()=>api.dio.interceptors.clear());
  tearDown(()=>api.dio.interceptors.clear());

  testWidgets('payment cannot be started before reservation loads and can retry offline', (tester)async{
    var attempts=0;
    api.dio.interceptors.add(InterceptorsWrapper(onRequest:(request,handler){
      if(++attempts==1){handler.reject(DioException(requestOptions:request,type:DioExceptionType.connectionError));}
      else{handler.resolve(Response(requestOptions:request,statusCode:200,data:{'customer_total_amount_minor':4200,'payment_status':'CAPTURED'}));}
    }));
    await tester.pumpWidget(const MaterialApp(home:PaymentScreen(bookingId:'booking-1')));
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'Payer maintenant')).onPressed,isNull);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(attempts,2);
    expect(find.text('Ce paiement est déjà réglé.'),findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'Payer maintenant')).onPressed,isNull);
  });

  testWidgets('payment recap fits a small screen with enlarged text',(tester)async{
    tester.view.physicalSize=const Size(320,640);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest:(request,handler)=>handler.resolve(Response(requestOptions:request,statusCode:200,data:{'customer_total_amount_minor':123456,'payment_status':'PENDING'}))));
    await tester.pumpWidget(MaterialApp(builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:const TextScaler.linear(1.5)),child:child!),home:const PaymentScreen(bookingId:'booking-2')));
    await tester.pumpAndSettle();
    expect(tester.takeException(),isNull);
  });
}
