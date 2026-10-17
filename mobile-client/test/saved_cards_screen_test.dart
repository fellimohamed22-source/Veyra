import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/core/widgets/saved_cards_screen.dart';

void main(){
  testWidgets('lists saved cards with brand, last four digits and expiry only',(tester)async{
    await tester.pumpWidget(MaterialApp(home:SavedCardsScreen(
      load:()async=>[{'id':'pm_1','brand':'visa','last4':'4242','expMonth':4,'expYear':2029}],
      remove:(_)async{},
    )));
    await tester.pumpAndSettle();
    expect(find.text('VISA •••• 4242'),findsOneWidget);
    expect(find.textContaining('04/29'),findsOneWidget);
  });

  testWidgets('removing a card asks for confirmation then reloads',(tester)async{
    var cards=[{'id':'pm_1','brand':'visa','last4':'4242','expMonth':4,'expYear':2029}];
    String? removed;
    await tester.pumpWidget(MaterialApp(home:SavedCardsScreen(
      load:()async=>List.of(cards),
      remove:(id)async{removed=id;cards=[];},
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer').last);
    await tester.pumpAndSettle();
    expect(removed,'pm_1');
    expect(find.textContaining('Aucune carte enregistrée'),findsOneWidget);
  });
}
