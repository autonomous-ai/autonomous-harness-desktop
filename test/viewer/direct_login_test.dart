import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/viewer/direct_auth.dart';
import 'package:harness/viewer/direct_auth_api.dart';
import 'package:harness/viewer/direct_login.dart';

import 'memory_key_value_store.dart';

/// The backend's two sign-in endpoints, answering as the real ones do.
class _FakeSso extends DirectAuthApi {
  _FakeSso() : super(config: AppConfig.dev);

  String? redirectUri;
  final exchanged = <String>[];

  @override
  Future<({String authorizeUrl, String tx})> authorizeNative(
    String redirectUri,
  ) async {
    this.redirectUri = redirectUri;
    return (authorizeUrl: 'https://sso.example/authorize', tx: 'tx-1');
  }

  @override
  Future<IssuedTokens> exchange({
    required String code,
    required String state,
    required String tx,
  }) async {
    exchanged.add('$code/$state/$tx');
    return const IssuedTokens(token: 'access', refreshToken: 'refresh', expiresIn: 3600);
  }
}

/// What the person's browser does once the SSO page is done with them.
Future<int> _browserOpens(String url) async {
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(Uri.parse(url))).close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close();
  }
}

void main() {
  late AuthSession session;
  late _FakeSso sso;
  late DirectLogin login;

  setUp(() {
    session = AuthSession(storage: MemoryKeyValueStore());
    sso = _FakeSso();
    login = DirectLogin(auth: DirectAuth(session: session, api: sso));
  });

  test('the redirect lands on the loopback listener and the tokens are kept', () async {
    String? shown;
    await login.login(
      onAuthorizeUrl: (url) {
        shown = url;
        unawaited(_browserOpens('${sso.redirectUri}?code=c1&state=s1'));
      },
    );
    expect(shown, 'https://sso.example/authorize');
    expect(sso.redirectUri, startsWith('http://127.0.0.1:'));
    expect(sso.exchanged, ['c1/s1/tx-1']);
    expect(await session.accessToken(), 'access');
    expect((await login.checkStatus()).loggedIn, isTrue);
  });

  test('a stray request (the favicon) is turned away and does not end it', () async {
    await login.login(
      onAuthorizeUrl: (_) async {
        final base = Uri.parse(sso.redirectUri!);
        expect(await _browserOpens(base.replace(path: '/favicon.ico').toString()), 404);
        await _browserOpens('${sso.redirectUri}?code=c2&state=s2');
      },
    );
    expect(sso.exchanged, ['c2/s2/tx-1']);
  });

  test('an SSO refusal fails the sign-in with its reason', () async {
    await expectLater(
      login.login(
        onAuthorizeUrl: (_) =>
            unawaited(_browserOpens('${sso.redirectUri}?error=access_denied')),
      ),
      throwsA(isA<DirectAuthException>().having((e) => e.message, 'message', contains('access_denied'))),
    );
    expect(await session.accessToken(), isNull);
  });

  test('cancel ends a sign-in still waiting on the browser', () async {
    await expectLater(
      login.login(onAuthorizeUrl: (_) => login.cancel()),
      throwsA(isA<DirectAuthException>()),
    );
  });

  test('signing out forgets the session', () async {
    await session.saveLogin(token: 'access');
    await login.logout();
    expect((await login.checkStatus()).loggedIn, isFalse);
  });
}
