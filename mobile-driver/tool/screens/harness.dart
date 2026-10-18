// Banc de captures UI : rend un écran Flutter en PNG (polices réelles) pour
// le comparer aux planches de maquettes. Hors `flutter test` (dossier tool/)
// car les rendus d'images dépendent de la plateforme. Usage :
//   flutter test tool/screens/<fichier>_test.dart --update-goldens
// Les PNG sont écrits dans tool/screens/out/ (ignoré par git).
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/main.dart';

Future<void> loadAppFonts() async {
  final jakarta = FontLoader('PlusJakartaSans');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    jakarta.addFont(rootBundle.load('assets/fonts/PlusJakartaSans-$w.ttf'));
  }
  await jakarta.load();
  final icons = FontLoader('MaterialIcons');
  icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}

/// Answers every API call with [respond] (path, method, data) -> body.
void fakeApi(Object? Function(String path, String method, Object? data) respond) {
  // The bench is a test harness run with flutter test, outside test/.
  // ignore: invalid_use_of_visible_for_testing_member
  FlutterSecureStorage.setMockInitialValues({'accessToken': 'test', 'refreshToken': 'test'});
  api.dio.interceptors.clear();
  api.dio.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
    h.resolve(Response(requestOptions: r, statusCode: 200, data: respond(r.path, r.method, r.data)));
  }));
}

final _root = GlobalKey();

/// Renders [app] on a 390x844 pt phone (x2) and writes out/[name].png.
Future<void> shot(WidgetTester tester, Widget app, String name, {Future<void> Function(WidgetTester)? before}) async {
  tester.view.physicalSize = const Size(780, 1688);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(RepaintBoundary(key: _root, child: app));
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
  if (before != null) await before(tester);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
  await expectLater(find.byKey(_root), matchesGoldenFile('out/$name.png'));
}
