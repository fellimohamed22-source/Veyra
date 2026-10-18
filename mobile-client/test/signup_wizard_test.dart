import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:veyra_client/main.dart';
import 'package:veyra_client/app/theme.dart';

void main() {
  testWidgets('signup runs the 3 board steps and sends an E.164 phone', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    FlutterSecureStorage.setMockInitialValues({});
    Map<String, dynamic>? body;
    String? verifiedPhone;
    api.dio.interceptors.clear();
    addTearDown(api.dio.interceptors.clear);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      if (r.path.endsWith('/register')) body = Map<String, dynamic>.from(r.data as Map);
      h.resolve(Response(requestOptions: r, statusCode: 200, data: {'accessToken': 'a', 'refreshToken': 'r'}));
    }));
    final router = GoRouter(initialLocation: '/register', routes: [
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/verify-phone', builder: (_, s) {
        verifiedPhone = s.extra as String?;
        return const Scaffold(body: Text('SMS'));
      }),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(theme: veyraTheme(), routerConfig: router,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.5)), child: child!)));
    await tester.pumpAndSettle();
    expect(find.text('1/3'), findsOneWidget);

    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();
    expect(find.text('1/3'), findsOneWidget);
    expect(find.text('Prénom requis'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('first-name')), 'Sophie');
    await tester.enterText(find.byKey(const ValueKey('last-name')), 'Martin');
    await tester.enterText(find.byKey(const ValueKey('phone')), '06 12 34 56 78');
    await tester.enterText(find.byKey(const ValueKey('email')), 'sophie@example.com');
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();
    expect(find.text('2/3'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('password')), 'motdepasse');
    await tester.enterText(find.byKey(const ValueKey('password-confirm')), 'motdepasse');
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();
    expect(find.text('2/3'), findsOneWidget);
    expect(find.text('Le mot de passe ne respecte pas encore toutes les règles.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('password')), 'Voyage2026!');
    await tester.enterText(find.byKey(const ValueKey('password-confirm')), 'Voyage2026!');
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();
    expect(find.text('3/3'), findsOneWidget);

    await tester.tap(find.text('Créer mon compte'));
    await tester.pumpAndSettle();
    expect(body, isNull);
    expect(find.text('Acceptation obligatoire'), findsNWidgets(2));

    await tester.tap(find.text('J’accepte les conditions d’utilisation.'));
    await tester.tap(find.text('J’accepte la politique de confidentialité.'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Créer mon compte'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(body?['phone'], '+33612345678');
    expect(body?['marketingOptIn'], isFalse);
    expect(verifiedPhone, '+33612345678');
    expect(tester.takeException(), isNull);
  });
}
