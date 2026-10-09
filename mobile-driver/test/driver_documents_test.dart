import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/core/widgets/driver_documents.dart';

void main() {
  testWidgets('offline document list shows a retry, not an empty dossier',
      (tester) async {
    var retries = 0;
    final documents = Completer<List<dynamic>>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DriverDocuments(
      documents: documents.future,
      onRetry: () => retries++,
    ))));
    documents.completeError(DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.connectionError));
    await tester.pumpAndSettle();
    expect(
        find.text('Aucun document envoyé. Complétez votre dossier chauffeur.'),
        findsNothing);
    await tester.tap(find.text('Réessayer'));
    expect(retries, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('documents use readable names and status on a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? selected;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DriverDocuments(
      documents: Future.value([
        {
          'type': 'IDENTITY',
          'status': 'SUBMITTED',
          'original_filename': 'identite.pdf'
        }
      ]),
      onRetry: () {},
      onUpload: (type) => selected = type,
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Pièce d’identité'), findsOneWidget);
    expect(find.text('identite.pdf • En vérification'), findsOneWidget);
    expect(find.text('IDENTITY'), findsNothing);
    await tester.tap(find.byTooltip('Téléverser'));
    expect(selected, 'IDENTITY');
    expect(tester.takeException(), isNull);
  });
}
