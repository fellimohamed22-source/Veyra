import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/core/widgets/pin_display.dart';

void main() {
  testWidgets('PIN keeps leading zero and fits narrow screen with large text',
      (tester) async {
    tester.view.physicalSize = const Size(280, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(20),
          child: VeyraPinDisplay(pin: '0427'),
        ),
      ),
    ));
    for (final digit in ['0', '4', '2', '7']) {
      expect(find.text(digit), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
