import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/main.dart';

void main(){
  testWidgets('registration validates email while typing and preserves the input',(tester)async{
    await tester.pumpWidget(const MaterialApp(home:RegisterScreen()));
    final email=find.widgetWithText(TextFormField,'Email');
    await tester.enterText(email,'adresse-invalide');
    await tester.pumpAndSettle();
    expect(find.text('E-mail invalide'),findsOneWidget);
    await tester.enterText(email,'client@example.com');
    await tester.pumpAndSettle();
    expect(find.text('E-mail invalide'),findsNothing);
    expect(find.text('client@example.com'),findsOneWidget);
    expect(find.text('Prénom requis'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
}
