import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/main.dart';

void main(){
  tearDown(()=>api.dio.interceptors.clear());
  test('no-show starts after the later of arrival and scheduled pickup',(){
    expect(noShowAvailableAt({'arrived_at':'2026-09-29T10:10:00Z','scheduled_at':'2026-09-29T10:00:00Z'}),DateTime.parse('2026-09-29T10:25:00Z'));
    expect(noShowAvailableAt({'arrived_at':'2026-09-29T09:55:00Z','scheduled_at':'2026-09-29T10:00:00Z'}),DateTime.parse('2026-09-29T10:15:00Z'));
    expect(noShowAvailableAt({}),isNull);
  });
  testWidgets('road distance remains visible without GPS and total is not invented',(tester)async{
    api.dio.interceptors.clear();
    api.dio.interceptors.add(InterceptorsWrapper(onRequest:(request,handler)=>handler.resolve(Response(requestOptions:request,statusCode:200,data:{'distanceMeters':12000,'durationSeconds':1200}))));
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:OpportunityDistanceSummary(booking:const {'pickup_lat':43,'pickup_lng':6,'dropoff_lat':44,'dropoff_lng':7},position:Future.value(null)))));
    await tester.pumpAndSettle();
    expect(find.text('Course : 12,0 km • 20 min'),findsOneWidget);
    expect(find.textContaining('vérifier le GPS'),findsOneWidget);
    expect(find.textContaining('Distance totale'),findsNothing);
    expect(tester.takeException(),isNull);
  });
}
