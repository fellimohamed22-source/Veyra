import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra_client/api.dart';

class Adapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions) respond;
  Adapter(this.respond);
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? body,
          Future<void>? cancelFuture) =>
      respond(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody json(String body, int status) =>
    ResponseBody.fromString(body, status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues(
      {'accessToken': 'old', 'refreshToken': 'refresh-old'}));
  test('simultaneous unauthorized requests share one refresh and both retry',
      () async {
    final entered = Completer<void>(), release = Completer<void>();
    var refreshCount = 0;
    final refresh = Dio();
    refresh.httpClientAdapter = Adapter((request) async {
      refreshCount++;
      if (!entered.isCompleted) entered.complete();
      await release.future;
      return json('{"accessToken":"new","refreshToken":"refresh-new"}', 200);
    });
    final api = Api('https://test.invalid', refreshClient: refresh);
    api.dio.httpClientAdapter = Adapter((request) async =>
        request.headers['Authorization'] == 'Bearer new'
            ? json('{}', 200)
            : json('{}', 401));
    final pending = Future.wait([api.dio.get('/one'), api.dio.get('/two')]);
    await entered.future;
    release.complete();
    final responses = await pending;
    expect(refreshCount, 1);
    expect(responses.map((r) => r.statusCode), everyElement(200));
    expect(await api.storage.read(key: 'refreshToken'), 'refresh-new');
    api.dio.close();
    refresh.close();
  });
  test('refresh network failure retains tokens and exposes the network error',
      () async {
    final refresh = Dio();
    refresh.httpClientAdapter = Adapter((request) async {
      throw DioException(
          requestOptions: request, type: DioExceptionType.connectionError);
    });
    final api = Api('https://test.invalid', refreshClient: refresh);
    api.dio.httpClientAdapter = Adapter((_) async => json('{}', 401));
    await expectLater(
        api.dio.get('/one'),
        throwsA(isA<DioException>()
            .having((e) => e.type, 'type', DioExceptionType.connectionError)));
    expect(await api.storage.read(key: 'refreshToken'), 'refresh-old');
    api.dio.close();
    refresh.close();
  });
  test('a refresh completed after logout cannot recreate the session',
      () async {
    final entered = Completer<void>(), release = Completer<void>();
    final refresh = Dio();
    refresh.httpClientAdapter = Adapter((request) async {
      entered.complete();
      await release.future;
      return json('{"accessToken":"new","refreshToken":"refresh-new"}', 200);
    });
    final api = Api('https://test.invalid', refreshClient: refresh);
    api.dio.httpClientAdapter = Adapter((_) async => json('{}', 401));
    final pending =
        expectLater(api.dio.get('/one'), throwsA(isA<DioException>()));
    await entered.future;
    await api.storage.deleteAll();
    release.complete();
    await pending;
    expect(await api.storage.read(key: 'accessToken'), isNull);
    api.dio.close();
    refresh.close();
  });
}
