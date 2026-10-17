import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/core/widgets/phone_verification_screen.dart';

void main(){
  test('French and international numbers are normalised to E.164',(){
    expect(PhoneVerificationScreen.toE164('06 12 34 56 78'),'+33612345678');
    expect(PhoneVerificationScreen.toE164('+33 6 12 34 56 78'),'+33612345678');
    expect(PhoneVerificationScreen.toE164('+44 7911 123456'),'+447911123456');
    expect(PhoneVerificationScreen.toE164('12345'),isNull);
  });

  testWidgets('sends the code, confirms it and submits the Firebase token',(tester)async{
    String? sentTo,submitted;
    var done=false;
    await tester.pumpWidget(MaterialApp(home:PhoneVerificationScreen(
      initialPhone:'06 12 34 56 78',
      sendCode:(e164)async{sentTo=e164;return 'verif-1';},
      confirm:(id,code)async=>'token-$id-$code',
      submit:(token)async{submitted=token;},
      onDone:()=>done=true,
      onLater:(){},
    )));
    await tester.tap(find.text('Envoyer le code'));
    await tester.pumpAndSettle();
    expect(sentTo,'+33612345678');
    await tester.enterText(find.byKey(const ValueKey('code-field')),'123456');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(submitted,'token-verif-1-123456');
    expect(done,isTrue);
  });

  testWidgets('a wrong code shows an error and does not finish',(tester)async{
    var done=false;
    await tester.pumpWidget(MaterialApp(home:PhoneVerificationScreen(
      initialPhone:'+33612345678',
      sendCode:(_)async=>'verif-1',
      confirm:(_, __)async=>throw Exception('invalid-verification-code'),
      submit:(_)async{},
      onDone:()=>done=true,
      onLater:(){},
    )));
    await tester.tap(find.text('Envoyer le code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('code-field')),'000000');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(find.text('Code incorrect ou expiré.'),findsOneWidget);
    expect(done,isFalse);
  });
}
