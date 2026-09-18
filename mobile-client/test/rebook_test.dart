import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/main.dart';

void main(){
  testWidgets('repeat booking keeps the route but requires a fresh departure',(tester)async{
    final interceptors=api.dio.interceptors.toList();
    api.dio.interceptors.clear();
    var publications=0;
    api.dio.interceptors.add(InterceptorsWrapper(onRequest:(request,handler){
      if(request.method=='POST')publications++;
      final path=request.path;
      final data=path.contains('vehicle-categories')
        ?[{'id':'category','display_name':'Berline','code':'SEDAN'}]
        :path.contains('routes/estimate')
          ?{'distanceMeters':12000,'durationSeconds':900}
          :{'mode':'BEST_VISIBLE'};
      handler.resolve(Response(requestOptions:request,statusCode:200,data:data));
    }));
    addTearDown((){api.dio.interceptors.clear();api.dio.interceptors.addAll(interceptors);});
    tester.view.physicalSize=const Size(320,800);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home:AddressScreen(prefill:{
      'pickup_address':'Marseille','dropoff_address':'Aix-en-Provence',
      'pickup_lat':43.3,'pickup_lng':5.4,'dropoff_lat':43.5,'dropoff_lng':5.5,
      'category_id':'category','passenger_count':2,'baggage_count':1,
      'scheduled_at':'2020-01-01T10:00:00Z','payment_method':'CASH',
    })));
    await tester.pumpAndSettle();
    expect(find.text('Marseille'),findsWidgets);
    expect(find.text('Aix-en-Provence'),findsWidgets);
    expect(publications,0);
    expect(tester.takeException(),isNull);
  });
}
