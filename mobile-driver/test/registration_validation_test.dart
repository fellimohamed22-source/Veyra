import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/main.dart';
import 'package:veyra_driver/app/theme.dart';
import 'package:veyra_driver/onboarding/driver_signup_flow.dart';

/// Board 08 B: type, 7 steps, then « Dossier envoyé ».
void main() {
  late Directory tmp;
  late String file;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('veyra_doc');
    file = '${tmp.path}/doc.jpg';
    File(file).writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> tapNext(WidgetTester t) async {
    await t.tap(find.widgetWithText(FilledButton, 'Continuer'));
    await t.pumpAndSettle();
  }

  Future<void> pickDate(WidgetTester t, String key) async {
    await t.ensureVisible(find.byKey(ValueKey(key)));
    await t.tap(find.byKey(ValueKey(key)));
    await t.pumpAndSettle();
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
  }

  Future<void> tapTile(WidgetTester t, String key) async {
    await t.ensureVisible(find.byKey(ValueKey(key)));
    await t.tap(find.byKey(ValueKey(key)));
    // The upload reads the file for real: let that I/O finish.
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pumpAndSettle();
  }

  testWidgets('independent driver completes the 7 board steps and submits', (tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    FlutterSecureStorage.setMockInitialValues({});
    final calls = <String, dynamic>{};
    final uploads = <String>[];
    var submitAttempts = 0;
    var submitted = false;
    api.dio.interceptors.clear();
    addTearDown(api.dio.interceptors.clear);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      final path = r.path;
      if (path.endsWith('/driver/documents')) {
        final form = r.data as FormData;
        final f = {for (final e in form.fields) e.key: e.value};
        uploads.add('${f['type']}/${f['side'] ?? ''}/${f['subtype'] ?? ''}');
      } else if (path.endsWith('/onboarding/submit')) {
        submitAttempts++;
        if (submitAttempts == 1) {
          return h.reject(DioException(requestOptions: r, response: Response(requestOptions: r, statusCode: 422,
              data: {'code': 'DOSSIER_INCOMPLETE', 'missing': ['INSURANCE']})));
        }
      } else if (r.data is Map) {
        calls[path] = r.data;
      }
      if (path.contains('vehicle-categories')) {
        return h.resolve(Response(requestOptions: r, statusCode: 200, data: [{'id': 'cat-1', 'code': 'STANDARD', 'display_name': 'Confort'}]));
      }
      h.resolve(Response(requestOptions: r, statusCode: 200, data: {'accessToken': 'a', 'refreshToken': 'r', 'kycStatus': 'SUBMITTED'}));
    }));

    await tester.pumpWidget(MaterialApp(theme: veyraTheme(), home: DriverSignupFlow(
      api: api,
      pickFile: ({bool imageOnly = false}) async => file,
      onAccountCreated: () async {},
      onSubmitted: () => submitted = true,
      onExit: () {},
    )));
    await tester.pumpAndSettle();

    // B2: the independent path is the one this lot opens.
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Continuer')).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('kind-independent')));
    await tester.pumpAndSettle();
    await tapNext(tester);
    expect(find.text('1/8'), findsOneWidget);

    // B3: personal information creates the account.
    await tester.enterText(find.byKey(const ValueKey('first-name')), 'Karim');
    await tester.enterText(find.byKey(const ValueKey('last-name')), 'Benali');
    await pickDate(tester, 'birth-date');
    await tester.enterText(find.byKey(const ValueKey('phone')), '06 12 34 56 78');
    await tester.enterText(find.byKey(const ValueKey('email')), 'karim@example.com');
    await tester.enterText(find.byKey(const ValueKey('password')), 'Chauffeur2026!');
    await tapTile(tester, 'profile-photo');
    await tapNext(tester);
    expect(find.text('1/8'), findsOneWidget, reason: 'consents are mandatory');
    await tester.ensureVisible(find.text("J'accepte les conditions générales d'utilisation"));
    await tester.tap(find.text("J'accepte les conditions générales d'utilisation"));
    await tester.tap(find.text("J'accepte la politique de confidentialité"));
    await tester.pumpAndSettle();
    // Account creation also uploads the profile photo (real file I/O).
    await tester.tap(find.widgetWithText(FilledButton, 'Continuer'));
    for (var i = 0; i < 40 && find.text('2/8').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(find.text('2/8'), findsOneWidget);
    expect((calls['/api/v1/auth/register-driver'] as Map)['phone'], '+33612345678');
    expect((calls['/api/v1/driver/onboarding/profile'] as Map)['driverType'], 'INDEPENDENT');

    // B4: identity recto + verso, kept apart.
    await tapNext(tester);
    expect(find.text('2/8'), findsOneWidget);
    await tapTile(tester, 'IDENTITY-front');
    await tapTile(tester, 'IDENTITY-back');
    await tapNext(tester);
    expect(uploads, ['IDENTITY/FRONT/ID_CARD', 'IDENTITY/BACK/ID_CARD']);

    // B5: VTC card.
    await tester.enterText(find.byKey(const ValueKey('vtc-card')), '1234567890');
    await pickDate(tester, 'vtc-expiry');
    await tapTile(tester, 'VTC_CARD-front');
    await tapTile(tester, 'VTC_CARD-back');
    await tapNext(tester);
    expect(find.text('4/8'), findsOneWidget);

    // B6: licence.
    await tester.enterText(find.byKey(const ValueKey('license-number')), '12AB34567');
    await pickDate(tester, 'license-expiry');
    await tapTile(tester, 'DRIVING_LICENSE-front');
    await tapNext(tester);
    expect((calls['/api/v1/driver/onboarding/license'] as Map)['category'], 'B');

    // B7: company + insurance.
    await tester.enterText(find.byKey(const ValueKey('siren')), '123 456 789 00012');
    await tester.enterText(find.byKey(const ValueKey('address')), '123 rue de la Paix, 75008 Paris');
    await tapTile(tester, 'INSURANCE');
    await tapTile(tester, 'KBIS');
    await tapTile(tester, 'REVTC_CERTIFICATE');
    await tapNext(tester);
    final company = calls['/api/v1/driver/onboarding/company'] as Map;
    expect(company['siren'], '123456789');
    expect(company['siret'], '12345678900012');
    expect(company['legalName'], 'Karim Benali');
    expect(company['legalForm'], 'AUTO_ENTREPRENEUR');

    // B8: vehicle + registration certificate.
    await tester.tap(find.byKey(const ValueKey('category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confort').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('brand')), 'Mercedes-Benz');
    await tester.enterText(find.byKey(const ValueKey('model')), 'Classe E');
    await tester.tap(find.byKey(const ValueKey('year')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2022').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('plate')), 'ab-123-cd');
    await tapTile(tester, 'VEHICLE_REGISTRATION');
    await tapTile(tester, 'VEHICLE_INSURANCE');
    await tapNext(tester);
    final vehicle = calls['/api/v1/driver/onboarding/vehicles'] as Map;
    expect(vehicle['plateNumber'], 'AB-123-CD');
    expect(vehicle['seats'], 4);
    expect(vehicle['baggageCapacity'], 3);
    expect(find.text('7/8'), findsOneWidget);

    // Bank account for payouts (as Uber / Bolt): holder, IBAN, RIB.
    await tester.enterText(find.byKey(const ValueKey('bank-holder')), 'Karim Benali');
    await tester.enterText(find.byKey(const ValueKey('bank-iban')), 'FR76 3000 6000 0112 3456 7890 189');
    await tapTile(tester, 'RIB');
    await tapNext(tester);
    expect((calls['/api/v1/driver/onboarding/bank'] as Map)['holderName'], 'Karim Benali');
    expect(find.text('8/8'), findsOneWidget);

    // B9: summary, charter, then submission.
    await tester.tap(find.widgetWithText(FilledButton, 'Envoyer mon dossier'));
    await tester.pumpAndSettle();
    expect(submitAttempts, 0, reason: 'charter not accepted yet');
    await tester.tap(find.byKey(const ValueKey('charter')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Envoyer mon dossier'));
    await tester.pumpAndSettle();
    expect(find.textContaining('attestation d’assurance'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Envoyer mon dossier'));
    await tester.pumpAndSettle();
    expect(find.text('Dossier envoyé !'), findsOneWidget);
    await tester.tap(find.text('Voir mon statut'));
    expect(submitted, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('affiliated driver joins a company with its code (board 08 C, 6 steps)', (tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    FlutterSecureStorage.setMockInitialValues({});
    final calls = <String, dynamic>{};
    final uploads = <String>[];
    var joined = false;
    api.dio.interceptors.clear();
    addTearDown(api.dio.interceptors.clear);
    const card = {'company_id': 'co-1', 'legal_name': 'Transports Prestige', 'address': 'Paris, France', 'siren': '987654321'};
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      final path = r.path;
      if (path.endsWith('/driver/documents')) {
        final form = r.data as FormData;
        final f = {for (final e in form.fields) e.key: e.value};
        uploads.add('${f['type']}/${f['side'] ?? ''}');
      } else if (r.data is Map) {
        calls[path] = r.data;
      }
      if (path.endsWith('/driver/company/lookup')) {
        return r.queryParameters['code'] == 'PRST-7Q4K'
            ? h.resolve(Response(requestOptions: r, statusCode: 200, data: card))
            : h.reject(DioException(requestOptions: r, response: Response(requestOptions: r, statusCode: 404, data: {'code': 'INVITE_CODE_INVALID'})));
      }
      if (path.endsWith('/driver/company/join')) joined = true;
      if (path.endsWith('/driver/company') && r.method == 'GET') {
        return h.resolve(Response(requestOptions: r, statusCode: 200, data: {...card, 'status': 'PENDING', 'vehicles': []}));
      }
      h.resolve(Response(requestOptions: r, statusCode: 200, data: {'accessToken': 'a', 'refreshToken': 'r', 'kycStatus': 'SUBMITTED'}));
    }));

    var submitted = false;
    await tester.pumpWidget(MaterialApp(theme: veyraTheme(), home: DriverSignupFlow(
      api: api,
      pickFile: ({bool imageOnly = false}) async => file,
      onAccountCreated: () async {},
      onSubmitted: () => submitted = true,
      onExit: () {},
    )));
    await tester.pumpAndSettle();

    // C1: affiliated type.
    await tester.tap(find.byKey(const ValueKey('kind-affiliated')));
    await tester.pumpAndSettle();
    await tapNext(tester);
    expect(find.text('1/7'), findsOneWidget);

    // C2: personal information.
    await tester.enterText(find.byKey(const ValueKey('first-name')), 'Sophie');
    await tester.enterText(find.byKey(const ValueKey('last-name')), 'Dubois');
    await pickDate(tester, 'birth-date');
    await tester.enterText(find.byKey(const ValueKey('phone')), '06 12 34 56 78');
    await tester.enterText(find.byKey(const ValueKey('email')), 'sophie@example.com');
    await tester.enterText(find.byKey(const ValueKey('password')), 'Chauffeur2026!');
    await tester.ensureVisible(find.text("J'accepte les conditions générales d'utilisation"));
    await tester.tap(find.text("J'accepte les conditions générales d'utilisation"));
    await tester.tap(find.text("J'accepte la politique de confidentialité"));
    await tester.pumpAndSettle();
    await tapNext(tester);
    expect((calls['/api/v1/driver/onboarding/profile'] as Map)['driverType'], 'AFFILIATED');

    // C3, C4: identity and VTC card.
    await tapTile(tester, 'IDENTITY-front');
    await tapTile(tester, 'IDENTITY-back');
    await tapNext(tester);
    await tester.enterText(find.byKey(const ValueKey('vtc-card')), '9876543210');
    await pickDate(tester, 'vtc-expiry');
    await tapTile(tester, 'VTC_CARD-front');
    await tapTile(tester, 'VTC_CARD-back');
    await tapNext(tester);
    expect(find.text('4/7'), findsOneWidget);

    // C5: invitation code, company card, join request.
    await tapNext(tester);
    expect(find.text('4/7'), findsOneWidget, reason: 'a company is required');
    await tester.enterText(find.byKey(const ValueKey('invite-code')), 'ZZZZ-9999');
    await tester.pumpAndSettle();
    expect(find.text('Code d’invitation invalide.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('invite-code')), 'PRST-7Q4K');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('selected-company')), findsOneWidget);
    expect(find.text('SIREN : 987 654 321'), findsOneWidget);
    await tapNext(tester);
    expect(joined, isTrue);
    expect((calls['/api/v1/driver/company/join'] as Map)['code'], 'PRST-7Q4K');
    expect(find.text('5/7'), findsOneWidget);

    // C6: licence and extra documents.
    await tester.enterText(find.byKey(const ValueKey('license-number')), '12AB34567');
    await pickDate(tester, 'license-expiry');
    await tapTile(tester, 'doc-license');
    await tapTile(tester, 'doc-address');
    await tapTile(tester, 'doc-photo');
    await tapNext(tester);
    expect(uploads, containsAll(['DRIVING_LICENSE/FRONT', 'PROOF_OF_ADDRESS/']));
    expect(find.text('6/7'), findsOneWidget);

    // Bank account step, then the summary.
    await tester.enterText(find.byKey(const ValueKey('bank-holder')), 'Sophie Dubois');
    await tester.enterText(find.byKey(const ValueKey('bank-iban')), 'FR7630006000011234567890189');
    await tapTile(tester, 'RIB');
    await tapNext(tester);
    expect(find.text('7/7'), findsOneWidget);

    // C7: summary with the company awaiting validation, then C8.
    expect(find.text('Transports Prestige'), findsOneWidget);
    expect(find.text('En attente de validation'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('charter')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Envoyer mon dossier'));
    await tester.pumpAndSettle();
    expect(find.text('Dossier envoyé !'), findsOneWidget);
    await tester.tap(find.text('Voir mon statut'));
    expect(submitted, isTrue);
    expect(tester.takeException(), isNull);
  });
}
