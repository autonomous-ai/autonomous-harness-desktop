import 'dart:convert';

import 'package:dio/dio.dart';

import '../api/api_client.dart' show ApiException;
import '../share/catalog_models.dart';
import 'grid_credentials.dart';
import 'grid_network.dart';
import 'grid_overview.dart';
import 'managed_network_member.dart';
import 'member_usage.dart';

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
  Future<GridMe> me() async =>
      GridMe.fromJson(Map<String, dynamic>.from(await _get('/v1/grid/me')));

  /// A key for one grid's relay, minted on demand.
  ///
  /// Not cached — see [GridCredentials] for why.
  Future<GridCredentials> credentials(String networkId) async =>
      GridCredentials.fromJson(
        Map<String, dynamic>.from(
          await _get('/v1/grid/networks/$networkId/credentials'),
        ),
      );

  /// The model ids this grid serves, in the order the relay lists them.
  ///
  /// The relay is OpenAI-compatible, so this is `GET {baseUrl}/models` — a
  /// different host and a different credential from every other call on this
  /// client, which is why it takes both explicitly rather than reading the
  /// session token.
  Future<List<String>> models({
    required String baseUrl,
    required String apiKey,
  }) async {
    final response = await _dio.getUri<dynamic>(
      Uri.parse('$baseUrl/models'),
      options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
    );
    final body = _unwrap(response);
    final data = body['data'];
    if (data is! List) return const [];
    return [
      for (final model in data)
        if (model is Map && model['id'] is String && model['id'] != '')
          model['id'] as String,
    ];
  }

  /// The model catalogue — every GGUF repo the shelf carries, searched and
  /// ranked by the control plane.
  ///
  /// A POST, and the body is the query: `sort` ranks (`trending`, `likes`,
  /// `created_at`) and `q` searches. Deliberately not the CLI's own
  /// `grid catalog`, which answers with a handful of picks ranked for this
  /// exact machine — that is a different question, asked elsewhere, and its
  /// answer is far too short to browse.
  Future<List<CatalogEntry>> catalog({
    String? sort,
    String? query,
    int pageSize = 50,
  }) async {
    final body = await _post('/v1/grid/catalog', {
      if (sort != null && sort.isNotEmpty) 'sort': sort,
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      'page_size': pageSize,
    });
    final models = body['models'];
    if (models is! List) return const [];
    return [
      for (final model in models)
        if (model is Map)
          CatalogEntry.fromJson(Map<String, dynamic>.from(model)),
    ];
  }

  /// One model, with every version it offers.
  ///
  /// [device] is this machine's hardware profile from `grid device-info`. With
  /// it each version comes back judged — runs here, too large, lower quality;
  /// without it they arrive unjudged, which is worse but not a reason to show
  /// nothing.
  Future<ModelDetail> catalogDetail(
    String repoId, {
    Map<String, dynamic>? device,
  }) async {
    final path = '/v1/grid/catalog/${Uri.encodeComponent(repoId)}';
    final query = device == null
        ? path
        : '$path?device=${Uri.encodeQueryComponent(jsonEncode(device))}';
    return ModelDetail.fromJson(Map<String, dynamic>.from(await _get(query)));
  }

  Future<Map<dynamic, dynamic>> _post(String path, Object body) async =>
      _unwrap(
        await _dio.post<dynamic>(
          path,
          data: body,
          options: Options(headers: {'Authorization': 'Bearer $_token'}),
        ),
      );

  /// What this grid is made of — its machines, its models and what they have
  /// answered.
  ///
  /// On the RELAY, not the control plane: the relay is the thing dispatching
  /// the work, so it is the only place that knows. Same host and same key as
  /// [models], which is why both take them explicitly.
  Future<GridOverview> overview({
    required String baseUrl,
    required String apiKey,
  }) async {
    final response = await _dio.getUri<dynamic>(
      Uri.parse('$baseUrl/grid/overview'),
      options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
    );
    return GridOverview.fromJson(
      Map<String, dynamic>.from(_unwrap(response)),
    );
  }

  /// Everyone on this grid.
  ///
  /// Owner-only on the server, which is not an error: a grid somebody else owns
  /// answers 403, and the rail then shows no member figure at all rather than a
  /// zero. That is why this returns null instead of throwing — "we may not ask"
  /// and "nobody is here" must not render the same.
  Future<List<ManagedNetworkMember>?> members(String networkId) async {
    try {
      final response = await _dio.get<dynamic>(
        '/v1/grid/managed-networks/$networkId/members',
        options: Options(headers: {'Authorization': 'Bearer $_token'}),
      );
      final status = response.statusCode ?? 0;
      if (status < 200 || status >= 300) return null;
      final body = response.data;
      // Either a `{"members": [...]}` envelope or a bare list.
      final rows = body is Map ? body['members'] : body;
      if (rows is! List) return null;
      return [
        for (final row in rows)
          if (row is Map)
            ManagedNetworkMember.fromJson(Map<String, dynamic>.from(row)),
      ];
    } on DioException {
      return null;
    }
  }

  /// What each person on this grid ran inside the relay's window.
  ///
  /// Authenticated with the RELAY key, unlike the roster beside it, because it
  /// names people rather than machines. Null means the relay reported no rollup
  /// — an older master, or one whose first query has not landed — which the
  /// panel renders differently from an empty map, the grid nobody used today.
  Future<({int windowSeconds, Map<String, MemberUsage> byEmail})?> memberUsage({
    required String baseUrl,
    required String apiKey,
  }) async {
    final response = await _dio.getUri<dynamic>(
      Uri.parse('$baseUrl/grid/members/usage'),
      options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
    );
    final body = _unwrap(response);
    final rows = body['members'];
    if (rows == null) return null;
    if (rows is! List) {
      throw ApiException('The relay sent a usage report we cannot read');
    }
    final window = body['window_seconds'];
    return (
      windowSeconds: window is num ? window.toInt() : 0,
      // Keyed by email, so a consumer the relay could not name is not in the
      // map — the roster is keyed by address and has nowhere to show them. They
      // are still counted by the grid's own token figure, which is why that one
      // can read higher than this list's total.
      byEmail: {
        for (final row in rows)
          if (MemberUsage.fromJson(row) case final usage?)
            if (usage.email case final email? when email.isNotEmpty)
              email.toLowerCase(): usage,
      },
    );
  }

  /// One authenticated GET against the control plane, unwrapped into a map or
  /// an [ApiException] — the shape every call above shares.
  Future<Map<dynamic, dynamic>> _get(String path) async => _unwrap(
    await _dio.get<dynamic>(
      path,
      options: Options(headers: {'Authorization': 'Bearer $_token'}),
    ),
  );

  Map<dynamic, dynamic> _unwrap(Response<dynamic> response) {
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
    return body;
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
