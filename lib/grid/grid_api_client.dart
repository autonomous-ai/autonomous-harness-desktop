import 'package:dio/dio.dart';

import '../api/api_client.dart' show ApiException;
import 'grid_network.dart';

/// The Grid control plane, called DIRECTLY — the one place in this app that
/// does.
///
/// Everything else goes through the local `harness` CLI on loopback (see
/// CLAUDE.md), because the CLI owns the Harness session and terminates E2EE.
/// Grid is a different backend with a different account, and the CLI proxies
/// none of it, so there is nothing to route through: this client holds its own
/// bearer token and talks to `api-grid.autonomous.ai` over HTTPS.
///
/// ⚠️ TODO(BE): [kGridSessionToken] is a HARDCODED session token — see it.
class GridApiClient {
  GridApiClient({Dio? dio, String? token})
    : _token = token ?? kGridSessionToken,
      _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: kGridApiBaseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              // Let the wrapper below turn HTTP failures into short,
              // user-facing ApiExceptions; transport failures stay
              // DioExceptions, the same split `ApiClient` uses.
              validateStatus: (status) =>
                  status != null && status >= 200 && status < 600,
            ),
          );

  final Dio _dio;
  final String _token;

  /// Who this token belongs to, and every grid it can talk to — one call, which
  /// is why this screen uses it rather than `/v1/grid/networks`: that endpoint
  /// returns the same list without the account behind it, and the pane names
  /// the account at the top.
  Future<GridMe> me() async {
    final response = await _dio.get<dynamic>(
      '/v1/grid/me',
      options: Options(headers: {'Authorization': 'Bearer $_token'}),
    );
    final body = response.data;
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw ApiException(_errorMessage(body, status), status: status);
    }
    if (body is! Map) {
      throw ApiException(
        'Grid returned an unexpected response',
        status: status,
      );
    }
    return GridMe.fromJson(Map<String, dynamic>.from(body));
  }

  /// FastAPI reports a failure as `{"detail": ...}`, where the detail is either
  /// a sentence or a list of validation objects. Anything else falls back to
  /// the status code, so a failure never surfaces as a blank message.
  static String _errorMessage(Object? body, int status) {
    if (status == 401 || status == 403) {
      return 'The Grid session token is not valid any more. Sign in again to '
          'refresh it.';
    }
    final detail = body is Map ? body['detail'] : null;
    if (detail is String && detail.trim().isNotEmpty) return detail.trim();
    return 'Grid request failed ($status)';
  }
}

/// Where the Grid control plane lives.
const kGridApiBaseUrl = 'https://api-grid.autonomous.ai';

/// ⚠️ TODO(BE): A HARDCODED Grid session token, and it must not ship.
///
/// This app has no Grid sign-in yet: the Harness CLI owns the *Harness*
/// session and knows nothing about Grid accounts, so there is nowhere to read a
/// real one from. Until a Grid login exists, the Grid screen runs on one
/// developer's session, pasted here.
///
/// What that means in practice, and why it is a temporary:
///
/// * It is a real credential in a git repository. Anyone with the checkout can
///   read this account's grids.
/// * It expires (`exp` 2027-08-19). After that the screen shows the
///   sign-in-again error above and there is no way to fix it from the app.
/// * Every user of a build made from this branch sees THIS account's grids,
///   not their own.
///
/// Override it without editing this file — which is how it should be used in
/// the meantime:
///
/// ```bash
/// flutter run -d macos --dart-define=GRID_API_TOKEN=<token>
/// ```
String get kGridSessionToken =>
    _tokenOverride.isEmpty ? _hardcodedToken : _tokenOverride;

const _tokenOverride = String.fromEnvironment('GRID_API_TOKEN');

const _hardcodedToken =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
    'eyJpc3MiOiJodHRwczovL2FwaS1ncmlkLmF1dG9ub21vdXMuYWkiLCJhdWQiOiJncmlkOndl'
    'YnNpdGUtc2Vzc2lvbiIsInN1YiI6IjEwNzIxNzIzNjgyOTQ4NjYxMTg5NSIsImVtYWlsIjoi'
    'cGhhbW5nb2NodXkuMTk4OUBnbWFpbC5jb20iLCJuYW1lIjoiSHV5IFBoYW0iLCJpYXQiOjE3'
    'ODcyODMxNDUsImV4cCI6MTgxODgxOTE0NSwidHlwIjoiZ3JpZF9zZXNzaW9uIn0.'
    'f5sA3DDUg5RJdsxxO01_tK8P84QXtplyFKKPLx61jQw';
