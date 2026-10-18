import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/main.dart';
import 'package:veyra_driver/app/theme.dart';
import 'package:veyra_driver/core/widgets/welcome_hero.dart';
import 'harness.dart';

Widget _app(Widget home) => MaterialApp(theme: veyraTheme(), home: home, debugShowCheckedModeBanner: false);

void _signedOut() {
  fakeApi((_, __, ___) => {});
  // ignore: invalid_use_of_visible_for_testing_member
  FlutterSecureStorage.setMockInitialValues({});
}

void main() {
  setUpAll(loadAppFonts);
  testWidgets('driver welcome', (tester) async {
    _signedOut();
    await shot(tester, _app(const LoginScreen()), 'driver_01_welcome');
  });
  testWidgets('driver sign-in form', (tester) async {
    _signedOut();
    await shot(tester, _app(const LoginScreen()), 'driver_01b_login', before: (t) async {
      await t.tap(find.text('Se connecter'));
      for (var j = 0; j < 6; j++) {
        await t.pump(const Duration(milliseconds: 150));
      }
    });
  });
  // Runs only when the onboarding photo is present (originals pending).
  testWidgets('driver welcome with photo', (tester) async {
    if (!File(VeyraAssets.welcomeDriver).existsSync()) return;
    _signedOut();
    await shot(tester, _app(const LoginScreen()), 'driver_01_welcome_photo', before: (t) async {
      await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
      for (var j = 0; j < 6; j++) {
        await t.pump(const Duration(milliseconds: 150));
      }
    });
  });
}
