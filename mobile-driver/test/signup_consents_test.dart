import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/core/widgets/signup_consents.dart';

void main(){
  testWidgets('three distinct consents, none pre-checked, marketing optional',(tester)async{
    var terms=false,privacy=false,marketing=false;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:StatefulBuilder(builder:(context,setState)=>SignupConsents(
      acceptTerms:terms,acceptPrivacy:privacy,marketingOptIn:marketing,showErrors:true,
      onTerms:(v)=>setState(()=>terms=v),
      onPrivacy:(v)=>setState(()=>privacy=v),
      onMarketing:(v)=>setState(()=>marketing=v),
    )))));

    final boxes=tester.widgetList<CheckboxListTile>(find.byType(CheckboxListTile)).toList();
    expect(boxes.length,3);
    expect(boxes.every((b)=>b.value==false),isTrue);
    // Only the two mandatory consents show a required error.
    expect(find.text('Acceptation obligatoire'),findsNWidgets(2));

    await tester.tap(find.text("J'accepte les conditions générales d'utilisation"));
    await tester.tap(find.text("J'accepte la politique de confidentialité"));
    await tester.pump();
    expect(terms&&privacy,isTrue);
    expect(marketing,isFalse);
    expect(SignupConsents.mandatoryAccepted(terms,privacy),isTrue);
    expect(find.text('Acceptation obligatoire'),findsNothing);
  });

  test('mandatory consents require both terms and privacy',(){
    expect(SignupConsents.mandatoryAccepted(true,false),isFalse);
    expect(SignupConsents.mandatoryAccepted(false,true),isFalse);
    expect(SignupConsents.mandatoryAccepted(true,true),isTrue);
  });
}
