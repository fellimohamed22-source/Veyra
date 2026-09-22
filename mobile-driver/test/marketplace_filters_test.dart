import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/main.dart';

void main(){
  setUp(()=>api.dio.interceptors.clear());
  tearDown(()=>api.dio.interceptors.clear());
  testWidgets('category filter is sent to backend and reset clears it on small screens',(tester)async{
    tester.view.physicalSize=const Size(320,760);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final queries=<Map<String,dynamic>>[];
    api.dio.interceptors.add(InterceptorsWrapper(onRequest:(request,handler){
      if(request.path.contains('vehicle-categories')){
        handler.resolve(Response(requestOptions:request,statusCode:200,data:[{'id':'van','display_name':'Van familial'}]));
      }else{
        queries.add(Map.of(request.queryParameters));
        handler.resolve(Response(requestOptions:request,statusCode:200,data:[]));
      }
    }));
    await tester.pumpWidget(const MaterialApp(home:OpportunitiesScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filtres'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Toutes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Van familial').last);
    await tester.pumpAndSettle();
    expect(queries.last['categoryId'],'van');
    expect(queries.last['page'],0);
    await tester.ensureVisible(find.text('Réinitialiser').first);
    await tester.tap(find.text('Réinitialiser').first);
    await tester.pumpAndSettle();
    expect(queries.last.containsKey('categoryId'),isFalse);
    expect(tester.takeException(),isNull);
  });
}
