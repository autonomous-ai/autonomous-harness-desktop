import 'dart:convert';

import 'package:dio/dio.dart';

import '../api/api_client.dart' show ApiException;
import '../logging/http_log.dart';
import '../share/catalog_models.dart';
import 'grid_access_type.dart';
import 'grid_credentials.dart';
import 'grid_network.dart';
import 'grid_session.dart';
import 'grid_overview.dart';
import 'managed_network_member.dart';
import 'member_usage.dart';

/// The Grid control plane, called DIRECTLY — the one place in this app that
/// does.
///
/// Everything else goes through the local `harness` CLI on loopback (see
/// CLAUDE.md), because the CLI owns the Harness session and terminates E2EE.
/// Grid is a different backend with a different account, and the CLI proxies
/// none of it, so there is nothing to route through: this client talks to the
/// Grid control plane over HTTPS with the machine's own Grid session.
///
/// That session comes from [gridSessionStore] — the Grid CLI's
/// `~/.grid/credentials.toml`, read fresh on every request rather than captured
/// here. A client built while signed out and a client built before a
/// `grid logout` both have to tell the truth about the session that exists NOW,
/// and a `final String` set in a constructor cannot.
class GridApiClient {
  GridApiClient({Dio? dio, this.token, GridSessionStore? session})
    : _session = session ?? gridSessionStore,
      // Only the one this client makes: an injected Dio belongs to whoever
      // passed it in, and in the tests that is a mock with its own interceptors.
      _dio =
          dio ??
          attachHttpLog(
            Dio(
              BaseOptions(
                baseUrl:
                    (session ?? gridSessionStore).value?.apiBaseUrl ??
                    kGridApiBaseUrl,
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 30),
                // Let the wrapper below turn HTTP failures into short,
                // user-facing ApiExceptions; transport failures stay
                // DioExceptions, the same split `ApiClient` uses.
                validateStatus: (status) =>
                    status != null && status >= 200 && status < 600,
              ),
            ),
          );

  final Dio _dio;

  /// A token pinned for this client, used in place of the machine's session.
  /// Tests pass one.
  final String? token;

  final GridSessionStore _session;

  /// The dev override, for a build that wants to run against an account it has
  /// not signed into on this machine. Empty in a normal build, and — unlike the
  /// constant it replaced — not somewhere a credential can be committed: that
  /// one was a real session token pasted into this file, so every build made
  /// from this branch read one developer's grids.
  static const String _tokenOverride = String.fromEnvironment('GRID_API_TOKEN');

  /// The bearer for the next request, or null when this computer has no Grid
  /// session. Read per call — see the class comment.
  String? get _bearer {
    final pinned = token ?? _tokenOverride;
    if (pinned.isNotEmpty) return pinned;
    return _session.value?.token;
  }

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
        await _dio.post<dynamic>(path, data: body, options: _authorized()),
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
    return GridOverview.fromJson(Map<String, dynamic>.from(_unwrap(response)));
  }

  /// Everyone on this grid, or null when the roster is not ours to read.
  ///
  /// Owner-only on the server, which is not an error: a grid somebody else owns
  /// answers 403, and the rail then shows no member figure at all rather than a
  /// zero. That is why this swallows instead of throwing — "we may not ask"
  /// and "nobody is here" must not render the same.
  ///
  /// The share sheet calls [membersOrThrow] instead: a dialog opened *to* read
  /// the roster has to say why it is empty, where the rail only has to stop
  /// printing a figure.
  Future<List<ManagedNetworkMember>?> members(String networkId) async {
    try {
      return await membersOrThrow(networkId);
    } on Object {
      return null;
    }
  }

  /// [members], with the refusal left to reach the caller.
  Future<List<ManagedNetworkMember>> membersOrThrow(String networkId) async {
    final body = await _get(_membersPath(networkId));
    // Either a `{"members": [...]}` envelope or a bare list. `_get` insists on
    // a map, so a bare list arrives as the envelope's absence rather than here.
    final rows = body['members'];
    if (rows is! List) {
      throw ApiException('Grid sent a member list we cannot read');
    }
    return [
      for (final row in rows)
        if (row is Map)
          ManagedNetworkMember.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  /// Creates a managed (hosted) grid — `POST /v1/grid/managed-networks`.
  ///
  /// The account this call is made with becomes the grid's owner, so there is
  /// no owner argument: the bearer IS the answer.
  ///
  /// The name is validated by `gridNameError` before it gets here. The server
  /// applies the same rule, but answers a violation with a 4xx body that is a
  /// validation object rather than a sentence — checking first is what lets the
  /// dialog say which rule was broken.
  Future<GridNetwork> createNetwork({
    required String name,
    required GridAccessType type,
  }) async {
    final body = await _post(_managedPath, {
      'name': name,
      'network_type': type.wire,
    });
    return GridNetwork.fromJson(Map<String, dynamic>.from(body));
  }

  /// Deletes a grid — `DELETE /v1/grid/managed-networks/{id}`. Owner-only on
  /// the server, and irreversible: everyone on the grid loses it.
  ///
  /// Uses [_unwrapEmpty] rather than [_unwrap] for the reason [removeMember]
  /// does — the endpoint's answer is its status code, and insisting on a body
  /// it need not send would turn a success into an error.
  Future<void> deleteNetwork(String networkId) async {
    _unwrapEmpty(
      await _dio.delete<dynamic>(
        '$_managedPath/$networkId',
        options: _authorized(),
      ),
    );
  }

  /// Renames a grid — `PATCH /v1/grid/networks/{id}`.
  ///
  /// ⚠️ On `networks`, NOT `managed-networks`: the control plane keeps the
  /// managed routes for provisioning (create / delete / members) and serves an
  /// edit here. The two paths are one character apart and answer 404 for each
  /// other, so they are written down separately rather than derived.
  ///
  /// Only the display name changes — the grid keeps its id, so relay keys,
  /// joined nodes and every Base URL already handed out keep working.
  ///
  /// Uses [_unwrapEmpty], like [deleteNetwork]: the endpoint's answer is its
  /// status code, and the Grid app's own client reads no body on success
  /// either — insisting on one would turn a 204 into an error.
  Future<void> renameNetwork(String networkId, {required String name}) async {
    _unwrapEmpty(
      await _dio.patch<dynamic>(
        '$_networksPath/$networkId',
        data: {'name': name},
        options: _authorized(),
      ),
    );
  }

  static const String _managedPath = '/v1/grid/managed-networks';
  static const String _networksPath = '/v1/grid/networks';

  /// Invites [email] to this grid, or changes what they may already do.
  ///
  /// **One POST does both.** There is no `PATCH …/members/{email}`: the store
  /// writes `ON CONFLICT(network_id, email) DO UPDATE SET roles_json = …` and
  /// bumps `member_epoch`, so this endpoint upserts. Deliberately not
  /// DELETE-then-POST for a role change — a POST that failed after the DELETE
  /// succeeded would drop the person off the grid entirely.
  ///
  /// [roles] are wire values from [ManagedMemberRole]; `admin` is refused
  /// server-side, and so is any grant above the caller's own (403
  /// `role_above_caller`), which is why the app filters the picker rather than
  /// letting a choice 403 after the fact.
  Future<void> addMember(
    String networkId, {
    required String email,
    required List<String> roles,
  }) async {
    await _post(_membersPath(networkId), {'email': email, 'roles': roles});
  }

  /// Takes [email] off this grid. Owner-only on the server.
  ///
  /// A membership admitted by the grid's email domain has no row to delete —
  /// the control plane synthesises it — so the UI offers no Remove there rather
  /// than sending a call that would take nothing away.
  Future<void> removeMember(String networkId, {required String email}) async {
    _unwrapEmpty(
      await _dio.delete<dynamic>(
        '${_membersPath(networkId)}/${Uri.encodeComponent(email)}',
        options: _authorized(),
      ),
    );
  }

  static String _membersPath(String networkId) =>
      '$_managedPath/$networkId/members';

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
  Future<Map<dynamic, dynamic>> _get(String path) async =>
      _unwrap(await _dio.get<dynamic>(path, options: _authorized()));

  /// The bearer header, or a refusal that reads like a state rather than a
  /// crash. Signed out is an ordinary condition here — a fresh machine has
  /// never run `harness grid login` — and every caller of this client already
  /// shows an [ApiException] to the user.
  Options _authorized() {
    final bearer = _bearer;
    if (bearer == null || bearer.isEmpty) throw GridSignedOutException();
    return Options(headers: {'Authorization': 'Bearer $bearer'});
  }

  /// A call whose answer is its status code — a DELETE. Same failure shapes as
  /// [_unwrap], without insisting on a body the endpoint need not send.
  void _unwrapEmpty(Response<dynamic> response) {
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw ApiException(_errorMessage(response.data, status), status: status);
    }
  }

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

/// This computer has no Grid session, so there is nothing to call the control
/// plane with.
///
/// Its own type rather than a plain [ApiException] so the Grid pane can offer
/// the one thing that fixes it — a sign-in — instead of printing a sentence and
/// a Retry that would fail identically.
class GridSignedOutException extends ApiException {
  GridSignedOutException()
    : super("You're not signed in to Grid on this computer.", status: 401);
}
