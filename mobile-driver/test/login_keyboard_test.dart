import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/main.dart';

void main(){
  // Reported on a phone: the sign-in sheet overflowed (5.1 px) once the
  // keyboard was open, which also raised the diagnostic error banner.
  testWidgets('sign-in form fits above the keyboard',(t)async{
    t.view.devicePixelRatio=2.625;
    t.view.physicalSize=const Size(1080,2340);
    t.view.padding=const FakeViewPadding(top:63);
    addTearDown(t.view.reset);
    await t.pumpWidget(const DriverApp());
    await t.pumpAndSettle();
    await t.tap(find.text('Se connecter'));
    await t.pumpAndSettle();
    t.view.viewInsets=const FakeViewPadding(bottom:2340*.48);
    await t.pumpAndSettle();
    expect(t.takeException(),isNull);
    expect(find.text('Mot de passe'),findsOneWidget);
  });
}
