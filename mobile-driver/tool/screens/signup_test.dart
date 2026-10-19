import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/main.dart';
import 'package:veyra_driver/app/theme.dart';
import 'package:veyra_driver/onboarding/driver_signup_flow.dart';
import 'harness.dart';

final _key = GlobalKey<DriverSignupFlowState>();

Widget _app() => MaterialApp(
      theme: veyraTheme(),
      debugShowCheckedModeBanner: false,
      home: DriverSignupFlow(
        key: _key,
        api: api,
        pickFile: ({bool imageOnly = false}) async => null,
        onAccountCreated: () async {},
        onSubmitted: () {},
        onExit: () {},
      ),
    );

const _company = {'company_id': 'co', 'legal_name': 'Transports Prestige', 'address': 'Paris, France', 'siren': '987654321', 'status': 'PENDING'};

/// Jumps straight to [step] with representative data (no API calls).
Future<void> _goto(WidgetTester t, int step, {DriverKind kind = DriverKind.independent, bool sent = false}) async {
  final s = _key.currentState!;
  final affiliated = kind == DriverKind.affiliated;
  // Bench only: drives the wizard state directly.
  // ignore: invalid_use_of_protected_member
  s.setState(() {
    s.kind = kind;
    s.step = step;
    s.submitted = sent;
    s.firstName.text = affiliated ? 'Sophie' : 'Karim';
    s.lastName.text = affiliated ? 'Dubois' : 'Benali';
    s.birthDate = DateTime(1985, 3, 15);
    s.phone.text = '6 12 34 56 78';
    s.email.text = affiliated ? 'sophie.dubois@gmail.com' : 'karim.benali@gmail.com';
    s.vtcCard.text = '1234567890';
    s.vtcExpiry = DateTime(2026, 12, 31);
    s.licenseNumber.text = '12AB34567';
    s.licenseExpiry = DateTime(2030, 12, 31);
    s.sirenSiret.text = '123 456 789 00012';
    s.address.text = '123 Rue de la Paix, 75008 Paris';
    s.revtc.text = 'REVTC123456';
    s.categories = [{'id': 'c', 'display_name': 'Confort'}];
    s.categoryId = 'c';
    s.brand.text = 'Mercedes-Benz';
    s.model.text = 'Classe E';
    s.plate.text = 'AB-123-CD';
    s.vehicleYear = 2022;
    s.page('IDENTITY', 'FRONT').sent = step != DriverSignupFlowState.sIdentity && step > 0;
    s.page('IDENTITY', 'BACK').sent = step != DriverSignupFlowState.sIdentity && step > 0;
    if (affiliated) {
      s.inviteCode.text = 'PRST-7Q4K';
      s.selectedCompany = Map<String, dynamic>.from(_company);
      if (step == DriverSignupFlowState.sSummary) s.joinedCompany = Map<String, dynamic>.from(_company);
      s.page('DRIVING_LICENSE', 'FRONT').sent = true;
      s.page('VTC_CARD', 'FRONT').sent = true;
      s.page('AVATAR').sent = true;
    }
  });
  for (var j = 0; j < 4; j++) {
    await t.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  setUpAll(loadAppFonts);
  // Step identifiers of the wizard.
  final independent = {0: 'b2_type', DriverSignupFlowState.sInfo: 'b3_infos', DriverSignupFlowState.sIdentity: 'b4_identite', DriverSignupFlowState.sVtc: 'b5_vtc', DriverSignupFlowState.sLicense: 'b6_permis', DriverSignupFlowState.sCompany: 'b7_entreprise', DriverSignupFlowState.sVehicle: 'b8_vehicule', DriverSignupFlowState.sSummary: 'b9_recap'};
  independent.forEach((step, name) {
    testWidgets('driver signup $name', (tester) async {
      fakeApi((_, __, ___) => {});
      await shot(tester, _app(), 'signup_$name', before: (t) => _goto(t, step));
    });
  });
  final affiliated = {0: 'c1_type', DriverSignupFlowState.sInfo: 'c2_infos', DriverSignupFlowState.sJoin: 'c5_societe', DriverSignupFlowState.sExtraDocs: 'c6_documents', DriverSignupFlowState.sSummary: 'c7_recap'};
  affiliated.forEach((step, name) {
    testWidgets('driver signup $name', (tester) async {
      fakeApi((_, __, ___) => {});
      await shot(tester, _app(), 'signup_$name', before: (t) => _goto(t, step, kind: DriverKind.affiliated));
    });
  });
  testWidgets('driver signup c8_envoye', (tester) async {
    fakeApi((_, __, ___) => {});
    await shot(tester, _app(), 'signup_c8_envoye', before: (t) => _goto(t, DriverSignupFlowState.sSummary, kind: DriverKind.affiliated, sent: true));
  });
}
