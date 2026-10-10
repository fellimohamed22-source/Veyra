import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/core/widgets/password_dialog.dart';

void main() {
  testWidgets(
      'invalid password stays in dialog; valid input returns exact text',
      (tester) async {
    (String, String)? result;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () async {
                      result = await showDialog<(String, String)>(
                          context: context,
                          builder: (_) => const VeyraPasswordDialog());
                    },
                    child: const Text('Ouvrir'))))));
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('Mot de passe actuel requis.'), findsOneWidget);
    expect(find.text('10 caractères minimum.'), findsOneWidget);
    expect(result, isNull);
    await tester.enterText(
        find.byType(TextFormField).first, 'ancien mot de passe');
    await tester.enterText(find.byType(TextFormField).last, 'court');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.byType(VeyraPasswordDialog), findsOneWidget);
    expect(result, isNull);
    await tester.enterText(
        find.byType(TextFormField).last, ' nouveau mot de passe ');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(result, ('ancien mot de passe', ' nouveau mot de passe '));
    expect(find.byType(VeyraPasswordDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
