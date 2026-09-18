import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/main.dart';

void main(){
  testWidgets('existing offer loads without changing state during build on a narrow screen',(tester)async{
    final interceptors=api.dio.interceptors.toList();
    api.dio.interceptors.clear();
    api.dio.interceptors.add(InterceptorsWrapper(onRequest:(request,handler){
      handler.resolve(Response(requestOptions:request,statusCode:200,data:request.path.contains('/routes/')
        ?{'distanceMeters':14000,'durationSeconds':1200,'points':[]}
        :{'pickup_address':'Une très longue adresse de départ à Marseille','dropoff_address':'Une autre longue adresse de destination',
          'scheduled_at':'2026-10-01T10:00:00Z','hasActiveOffer':true,'ownActiveOfferAmountMinor':4000,
          'pickup_lat':43.3,'pickup_lng':5.4,'dropoff_lat':43.4,'dropoff_lng':5.5,'tripDistanceMeters':12000}));
    }));
    addTearDown((){api.dio.interceptors.clear();api.dio.interceptors.addAll(interceptors);});
    tester.view.physicalSize=const Size(320,800);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home:RequestScreen(bookingId:'booking')));
    await tester.pumpAndSettle();
    expect(tester.takeException(),isNull);
    await tester.scrollUntilVisible(find.byType(TextField),300);
    expect(find.text('40,00'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
}
