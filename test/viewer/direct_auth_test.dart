import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/viewer/direct_auth.dart';
import 'package:harness/viewer/direct_auth_api.dart';

import 'memory_key_value_store.dart';

class _FakeAuthApi extends DirectAuthApi {
  _FakeAuthApi() : super(config: AppConfig.dev);

  int refreshes = 0;
  Object? failWith;
  final gate = Completer<void>();

  @override
  Future<IssuedTokens> refresh(
    String refreshToken, {
    required String autonomousEnv,
  }) async {
    refreshes++;
    await gate.future;
    final failure = failWith;
    if (failure != null) throw failure;
    return const IssuedTokens(token: 'fresh', refreshToken: 'r2', expiresIn: 3600);
  }
}

void main() {
  late AuthSession session;
  late _FakeAuthApi api;
  late DirectAuth auth;

  setUp(() {
    session = AuthSession(storage: MemoryKeyValueStore());
    api = _FakeAuthApi();
    auth = DirectAuth(session: session, api: api);
  });

  Future<void> signIn({required int expiresIn}) => session.saveLogin(
    token: 'old',
    refreshToken: 'r1',
    expiresIn: expiresIn,
  );

  test('a token with time left is handed out as it is', () async {
    await signIn(expiresIn: 3600);
    expect(await auth.accessToken(), 'old');
    expect(api.refreshes, 0);
  });

  test('a token about to lapse is refreshed once, however many ask', () async {
    await signIn(expiresIn: 30);
    final asks = [auth.accessToken(), auth.accessToken(), auth.accessToken()];
    api.gate.complete();
    expect(await Future.wait(asks), ['fresh', 'fresh', 'fresh']);
    expect(api.refreshes, 1);
    expect(await session.accessToken(), 'fresh');
    expect(await session.refreshToken(), 'r2');
  });

  test('a refused token is refreshed; one already replaced is not', () async {
    await signIn(expiresIn: 3600);
    expect(await auth.accessToken(force: true, failedToken: 'older'), 'old');
    expect(api.refreshes, 0);
    api.gate.complete();
    expect(await auth.accessToken(force: true, failedToken: 'old'), 'fresh');
    expect(api.refreshes, 1);
  });

  test('a dead refresh token signs out', () async {
    await signIn(expiresIn: 30);
    api
      ..failWith = const DirectAuthException('expired', signedOut: true)
      ..gate.complete();
    await expectLater(
      auth.accessToken(),
      throwsA(isA<DirectAuthException>().having((e) => e.signedOut, 'signedOut', isTrue)),
    );
    expect(await auth.hasSession(), isFalse);
  });

  test('an outage keeps the session: its refresh token cannot be got back', () async {
    await signIn(expiresIn: 30);
    api
      ..failWith = const DirectAuthException('unavailable')
      ..gate.complete();
    await expectLater(auth.accessToken(), throwsA(isA<DirectAuthException>()));
    expect(await auth.hasSession(), isTrue);
    expect(await session.refreshToken(), 'r1');
  });

  test('no session at all is signed out, not an error to retry', () async {
    await expectLater(
      auth.accessToken(),
      throwsA(isA<DirectAuthException>().having((e) => e.signedOut, 'signedOut', isTrue)),
    );
  });
}
