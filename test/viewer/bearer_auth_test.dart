import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/api/access_token_source.dart';
import 'package:harness/api/api_client.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';

import 'memory_key_value_store.dart';

class _Tokens implements AccessTokenSource {
  String current = 'old';
  int refreshed = 0;

  @override
  Future<String> accessToken({bool force = false, String? failedToken}) async {
    if (force && failedToken == current) {
      refreshed++;
      current = 'fresh';
    }
    return current;
  }
}

void main() {
  late HttpServer backend;
  final seen = <({String? bearer, String? env})>[];

  setUp(() async {
    seen.clear();
    backend = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    backend.listen((request) async {
      final bearer = request.headers.value('authorization');
      seen.add((bearer: bearer, env: request.headers.value('x-autonomous-env')));
      final ok = bearer == 'Bearer fresh';
      request.response
        ..statusCode = ok ? 200 : 401
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(ok
            ? {'success': true, 'data': {'id': 'user-1'}}
            : {'success': false, 'error': {'message': 'expired'}}));
      await request.response.close();
    });
  });

  tearDown(() => backend.close(force: true));

  test('a viewer signs its REST calls, and retries a 401 once on a fresh token', () async {
    final tokens = _Tokens();
    final api = ApiClient(
      config: AppConfig(apiBaseUrl: 'http://127.0.0.1:${backend.port}'),
      session: AuthSession(storage: MemoryKeyValueStore()),
      auth: tokens,
    );
    expect(await api.me(), {'id': 'user-1'});
    expect(tokens.refreshed, 1);
    expect(seen, [
      (bearer: 'Bearer old', env: 'prod'),
      (bearer: 'Bearer fresh', env: 'prod'),
    ]);
  });
}
