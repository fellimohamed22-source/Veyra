import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/core/widgets/suggested_price_hint.dart';

void main(){
  testWidgets('shows the net range when a grid exists',(tester)async{
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:SuggestedPriceHint(
      load:()async=>{'available':true,'netLowMinor':5900,'netHighMinor':7400}))));
    await tester.pumpAndSettle();
    expect(find.text('Prix conseillé (net) : 59 € – 74 €'),findsOneWidget);
  });

  testWidgets('shows nothing without a grid or on error',(tester)async{
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:Column(children:[
      SuggestedPriceHint(load:()async=>{'available':false}),
      SuggestedPriceHint(load:()async=>throw Exception('offline')),
    ]))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Prix conseillé'),findsNothing);
    expect(tester.takeException(),isNull);
  });
}
