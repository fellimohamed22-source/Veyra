import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/app_locale.dart';
import 'package:veyra_client/main.dart';

void main() {
  testWidgets('the profile language row switches the whole UI to English', (tester) async {
    AppLocale.code.value = 'fr';
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ValueListenableBuilder<String>(
      valueListenable: AppLocale.code,
      builder: (_, __, ___) => Column(children: [const LanguageTile(), Text(t('Mes réservations'))]),
    ))));
    expect(find.text('Langue'), findsOneWidget);
    await tester.tap(find.byKey(const Key('lang-en')));
    await tester.pumpAndSettle();
    expect(AppLocale.code.value, 'en');
    expect(find.text('Language'), findsOneWidget);
    await tester.tap(find.byKey(const Key('lang-fr')));
    await tester.pumpAndSettle();
    expect(find.text('Langue'), findsOneWidget);
  });
}
