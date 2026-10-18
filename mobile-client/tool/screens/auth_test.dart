import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/main.dart';
import 'package:veyra_client/app/theme.dart';
import 'package:veyra_client/core/widgets/auth_ui.dart';
import 'package:veyra_client/core/widgets/phone_verification_screen.dart';
import 'harness.dart';

Widget _app(Widget home) => MaterialApp(theme: veyraTheme(), home: home, debugShowCheckedModeBanner: false);

// Signed-out bench: no stored token, so the welcome screen stays put.
void _signedOut() {
  fakeApi((_, __, ___) => {});
  // ignore: invalid_use_of_visible_for_testing_member
  FlutterSecureStorage.setMockInitialValues({});
}

Future<void> _settle(WidgetTester t) async {
  for (var j = 0; j < 6; j++) {
    await t.pump(const Duration(milliseconds: 150));
  }
}

Future<void> _fillStep1(WidgetTester t) async {
  await t.enterText(find.byKey(const ValueKey('first-name')), 'Sophie');
  await t.enterText(find.byKey(const ValueKey('last-name')), 'Martin');
  await t.enterText(find.byKey(const ValueKey('phone')), '6 12 34 56 78');
  await t.enterText(find.byKey(const ValueKey('email')), 'sophie.martin@gmail.com');
}

void main() {
  setUpAll(loadAppFonts);
  testWidgets('welcome', (tester) async {
    _signedOut();
    await shot(tester, _app(const LoginScreen()), 'auth_01_welcome');
  });
  testWidgets('login form', (tester) async {
    _signedOut();
    await shot(tester, _app(const LoginScreen()), 'auth_01b_login', before: (t) async {
      await t.tap(find.text('Se connecter'));
      await _settle(t);
    });
  });
  testWidgets('signup info', (tester) async {
    fakeApi((_, __, ___) => {});
    await shot(tester, _app(const RegisterScreen()), 'auth_02_info', before: _fillStep1);
  });
  testWidgets('signup password', (tester) async {
    fakeApi((_, __, ___) => {});
    await shot(tester, _app(const RegisterScreen()), 'auth_03_password', before: (t) async {
      await _fillStep1(t);
      await t.tap(find.text('Continuer'));
      await _settle(t);
      await t.enterText(find.byKey(const ValueKey('password')), 'Voyage2026!');
      await t.enterText(find.byKey(const ValueKey('password-confirm')), 'Voyage2026!');
    });
  });
  testWidgets('signup terms', (tester) async {
    fakeApi((_, __, ___) => {});
    await shot(tester, _app(const RegisterScreen()), 'auth_04_terms', before: (t) async {
      await _fillStep1(t);
      await t.tap(find.text('Continuer'));
      await _settle(t);
      await t.enterText(find.byKey(const ValueKey('password')), 'Voyage2026!');
      await t.enterText(find.byKey(const ValueKey('password-confirm')), 'Voyage2026!');
      await t.tap(find.text('Continuer'));
      await _settle(t);
      await t.tap(find.text('J’accepte les conditions d’utilisation.'));
      await t.tap(find.text('J’accepte la politique de confidentialité.'));
    });
  });
  testWidgets('sms', (tester) async {
    fakeApi((_, __, ___) => {});
    await shot(tester, _app(PhoneVerificationScreen(
      initialPhone: '+33612345678',
      sendCode: (_) async => 'v',
      confirm: (_, __) async => 't',
      submit: (_) async {},
      onDone: () {},
      onLater: () {},
    )), 'auth_05_sms', before: (t) async {
      await t.enterText(find.byKey(const ValueKey('code-field')), '123');
    });
  });
  testWidgets('created', (tester) async {
    fakeApi((_, __, ___) => {});
    await shot(tester, _app(Scaffold(body: VeyraSuccessView(
      title: 'Bienvenue sur VEYRA !',
      text: 'Votre compte client a été créé avec succès.',
      actionLabel: 'Commencer',
      onAction: () {},
    ))), 'auth_06_created');
  });
}
