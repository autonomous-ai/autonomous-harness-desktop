import '../api/access_token_source.dart';
import '../auth/auth_session.dart';
import 'direct_auth_api.dart';

/// A viewer build's SSO session — authSession.ts's `AuthSessionManager`, moved into the app because
/// a device with no harness CLI has nobody else to hold it: the tokens `/api/auth/exchange` issued,
/// kept in [AuthSession], refreshed [_refreshSkew] before they lapse, one refresh at a time.
class DirectAuth implements AccessTokenSource {
  DirectAuth({required this.session, required this.api});

  final AuthSession session;
  final DirectAuthApi api;
  Future<String>? _refreshing;

  static const _refreshSkew = Duration(seconds: 60);

  Future<bool> hasSession() async =>
      ((await session.accessToken()) ?? '').isNotEmpty;

  Future<void> signIn(IssuedTokens tokens) => session.saveLogin(
    token: tokens.token,
    refreshToken: tokens.refreshToken,
    autonomousEnv: tokens.autonomousEnv ?? api.config.autonomousEnv,
    expiresIn: tokens.expiresIn,
  );

  Future<void> signOut() => session.clear();

  @override
  Future<String> accessToken({bool force = false, String? failedToken}) async {
    final current = await session.accessToken();
    if (current == null || current.isEmpty) {
      throw const DirectAuthException('Not signed in.', signedOut: true);
    }
    // Someone else already refreshed past the token that failed — use theirs.
    if (failedToken != null && failedToken != current) return current;
    if (!force && !await _isStale()) return current;
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _isStale() async {
    final expiresAt = await session.accessTokenExpiresAt();
    return expiresAt != null &&
        expiresAt.isBefore(DateTime.now().toUtc().add(_refreshSkew));
  }

  Future<String> _refresh() async {
    final refreshToken = await session.refreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      await session.clear();
      throw const DirectAuthException(
        'Your sign-in expired. Sign in again.',
        signedOut: true,
      );
    }
    try {
      final autonomousEnv = await session.autonomousEnv();
      final tokens = await api.refresh(refreshToken, autonomousEnv: autonomousEnv);
      await session.saveRefresh(
        token: tokens.token,
        refreshToken: tokens.refreshToken,
        autonomousEnv: autonomousEnv,
        expiresIn: tokens.expiresIn,
      );
      return tokens.token;
    } on DirectAuthException catch (error) {
      if (error.signedOut) await session.clear();
      rethrow;
    }
  }
}
