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

/// Jumps straight to [step] with representative data (no API calls).
Future<void> _goto(WidgetTester t, int step, {DriverKind kind = DriverKind.independent}) async {
  final s = _key.currentState!;
  // Bench only: drives the wizard state directly.
  // ignore: invalid_use_of_protected_member
  s.setState(() {
    s.kind = kind;
    s.step = step;
    s.firstName.text = 'Karim';
    s.lastName.text = 'Benali';
    s.birthDate = DateTime(1985, 3, 15);
    s.phone.text = '6 12 34 56 78';
    s.email.text = 'karim.benali@gmail.com';
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
    s.page('IDENTITY', 'FRONT').sent = step > 2;
    s.page('IDENTITY', 'BACK').sent = step > 2;
  });
  for (var j = 0; j < 4; j++) {
    await t.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  setUpAll(loadAppFonts);
  final steps = {0: 'b2_type', 1: 'b3_infos', 2: 'b4_identite', 3: 'b5_vtc', 4: 'b6_permis', 5: 'b7_entreprise', 6: 'b8_vehicule', 7: 'b9_recap', 8: 'c8_envoye'};
  steps.forEach((step, name) {
    testWidgets('driver signup $name', (tester) async {
      fakeApi((_, __, ___) => {});
      await shot(tester, _app(), 'signup_$name', before: (t) => _goto(t, step));
    });
  });
}
