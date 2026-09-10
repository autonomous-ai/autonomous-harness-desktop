import 'package:dio/dio.dart';

import '../auth/auth_session.dart';
import '../core/config.dart';
import '../core/models.dart';
import '../logging/http_log.dart';
import 'access_token_source.dart';
import 'bearer_auth_interceptor.dart';

/// Control-plane REST client.
///
/// In a desktop build every call goes to the LOCAL `harness` CLI (loopback, no credential — see
/// CLAUDE.md's naming/architecture notes for why), which proxies to the real backend using its own
/// saved SSO session, and this app never holds a bearer token itself. A viewer build has no CLI:
/// given [auth], the same calls go straight to the backend, signed with the session the app holds.
/// Terminal bytes ride the WS path either way.
class ApiClient {
  final AppConfig config;
  final AuthSession session;
  final AccessTokenSource? auth;
  late final Dio _dio = _buildDio();

  ApiClient({required this.config, required this.session, this.auth});

  Dio _buildDio() {
    final dio = attachHttpLog(
      Dio(
        BaseOptions(
          baseUrl: auth == null ? config.localCliBaseUrl : config.apiBaseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          // Let the API wrapper turn HTTP failures into short, user-facing
          // ApiExceptions. Transport failures still surface as DioExceptions.
          validateStatus: (status) =>
              status != null && status >= 200 && status < 600,
        ),
      ),
    );
    final source = auth;
    if (source != null) {
      dio.interceptors.add(
        BearerAuthInterceptor(source, dio, autonomousEnv: config.autonomousEnv),
      );
    }
    return dio;
  }

  /// The CLI's loopback server takes a machine rename or delete only when marked as coming from
  /// this computer; the backend wants no such header.
  Options? get _machineWriteOptions =>
      auth == null ? Options(headers: {'x-adapter-local': '1'}) : null;

  // -- auth --
  Future<Map<String, dynamic>?> me() async {
    final res = await _dio.get('/api/auth/me');
    return unwrapApiResponse(res) as Map<String, dynamic>?;
  }

  // -- machines (control plane) --
  Future<List<Machine>> machines() async {
    final res = await _dio.get('/api/machines');
    final data = unwrapApiResponse(res) as Map<String, dynamic>;
    final list = data['machines'] as List<dynamic>? ?? [];
    return list
        .map((e) => Machine.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<String?> renameMachine({
    required String machineId,
    required String name,
  }) async {
    final res = await _dio.patch(
      '/api/machines/$machineId',
      data: {'name': name},
      options: _machineWriteOptions,
    );
    final data = unwrapApiResponse(res) as Map<String, dynamic>;
    return data['name'] as String?;
  }

  Future<void> deleteMachine({required String machineId}) async {
    final res = await _dio.delete(
      '/api/machines/$machineId',
      options: _machineWriteOptions,
    );
    unwrapApiResponse(res);
  }
}

/// The backend's `{success, data | error}` envelope — which the CLI passes through as it is — as
/// its `data`, or an [ApiException] carrying the server's own message.
dynamic unwrapApiResponse(Response<dynamic> res) {
  final body = res.data;
  if (body is Map && body['success'] == true) {
    return body['data'];
  }
  final error = body is Map ? body['error'] : null;
  final serverMessage = error is Map ? error['message'] : null;
  throw ApiException(
    serverMessage is String && serverMessage.isNotEmpty
        ? serverMessage
        : 'Request failed (${res.statusCode})',
    status: res.statusCode,
  );
}

class ApiException implements Exception {
  final String message;
  final int? status;
  ApiException(this.message, {this.status});
  @override
  String toString() => message;
}

bool isUnauthorizedError(Object error) =>
    error is DioException && error.response?.statusCode == 401 ||
    error is ApiException && error.status == 401;
