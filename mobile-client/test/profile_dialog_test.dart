import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/core/widgets/profile_dialog.dart';
import 'package:veyra_client/app/theme.dart';

void main() {
  testWidgets('profile validation retains dialog and entered data until valid',
      (tester) async {
    (String, String, String)? result;
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: veyraTheme(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!),
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () async {
                      result = await showDialog<(String, String, String)>(
                          context: context,
                          builder: (_) => const VeyraProfileDialog(
                              profile: {'last_name': 'Martin'}));
                    },
                    child: const Text('Ouvrir'))))));
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('Prénom requis.'), findsOneWidget);
    expect(
        find.text('Téléphone de 6 caractères minimum requis.'), findsOneWidget);
    expect(find.byType(VeyraProfileDialog), findsOneWidget);
    expect(result, isNull);
    await tester.enterText(find.byType(TextFormField).first, 'Chris');
    await tester.enterText(find.byType(TextFormField).last, '+33612345678');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(result, ('Chris', 'Martin', '+33612345678'));
    expect(find.byType(VeyraProfileDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
