import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_driver/main.dart';

// The base platform implementation throws if picking cannot be performed.
class UnavailablePicker extends FilePicker {}

void main() {
  testWidgets('document picker failure is visible and releases upload control',
      (tester) async {
    FilePicker.platform = UnavailablePicker();
    api.dio.interceptors.clear();
    addTearDown(api.dio.interceptors.clear);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      if (request.path.endsWith('/avatar')) {
        handler.reject(DioException(
            requestOptions: request,
            response: Response(requestOptions: request, statusCode: 404)));
        return;
      }
      handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: request.path.endsWith('/documents')
              ? [
                  {
                    'type': 'IDENTITY',
                    'status': 'SUBMITTED',
                    'original_filename': 'id.pdf'
                  }
                ]
              : {
                  'id': 'driver-user',
                  'first_name': 'Alex',
                  'kyc_status': 'SUBMITTED'
                }));
    }));
    await tester.pumpWidget(const MaterialApp(home: AccountScreen()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byTooltip('Téléverser'), 200);
    await tester.tap(find.byTooltip('Téléverser'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
    final upload = find
        .ancestor(
            of: find.byIcon(Icons.upload_file),
            matching: find.byType(IconButton))
        .first;
    expect(tester.widget<IconButton>(upload).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
