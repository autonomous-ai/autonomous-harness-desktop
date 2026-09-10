import 'package:dio/dio.dart';

import '../logging/http_log.dart';
import 'usage_credentials.dart';
import 'usage_source.dart';
import 'usage_window.dart';

/// Codex's rate limits, read with the token `codex login` left in
/// `~/.codex/auth.json`.
///
/// ⚠️ Undocumented, on the same terms as [ClaudeUsageSource]: this is the
/// backend the Codex CLI itself asks, and it can change without notice.
///
/// Codex numbers its windows rather than naming them — a primary and a
/// secondary, whose real durations arrive in the payload — so the labels here
/// are derived from `limit_window_seconds` instead of hardcoded. A build that
/// printed "5h" for a window the server had quietly changed to 24h would be
/// confidently wrong, which is worse than saying nothing.
class CodexUsageSource implements UsageSource {
  CodexUsageSource({Dio? dio, UsageCredentials? credentials})
    : _dio = dio ?? attachHttpLog(buildUsageDio()),
      _credentials = credentials ?? const UsageCredentials();

  final Dio _dio;
  final UsageCredentials _credentials;

  static const _url = 'https://chatgpt.com/backend-api/wham/usage';

  @override
  UsageProvider get provider => UsageProvider.codex;

  @override
  Future<ProviderUsage> read() async {
    final token = await _credentials.codex();
    if (token == null) return signedOut(provider);
    final accountId = await _credentials.codexAccountId();
    try {
      final response = await _dio.getUri<Object?>(
        Uri.parse(_url),
        options: Options(
          headers: {
            'Authorization': 'Bearer ${token.accessToken}',
            'ChatGPT-Account-Id': ?accountId,
          },
        ),
      );
      final failure = usageFailureFor(provider, response.statusCode);
      if (failure != null) return failure;
      final data = response.data;
      if (data is! Map) {
        return ProviderUsage(
          provider: provider,
          status: UsageStatus.failed,
          message: 'Codex answered in a shape this build cannot read',
        );
      }
      return _mapWindows(data);
    } on DioException {
      return usageFailureFor(provider, null)!;
    }
  }

  ProviderUsage _mapWindows(Map<Object?, Object?> data) {
    final limits = data['rate_limit'];
    final windows = limits is Map
        ? <UsageWindow>[
            ?_window(limits['primary_window']),
            ?_window(limits['secondary_window']),
          ]
        : const <UsageWindow>[];
    if (windows.isEmpty) {
      return ProviderUsage(
        provider: provider,
        status: UsageStatus.failed,
        message: 'Codex reported no limits',
      );
    }
    return ProviderUsage(
      provider: provider,
      status: UsageStatus.ok,
      windows: windows,
      fetchedAt: DateTime.now(),
    );
  }

  UsageWindow? _window(Object? raw) {
    if (raw is! Map) return null;
    final used = parseUsedPercent([raw['used_percent']]);
    if (used == null) return null;
    return UsageWindow(
      label: _labelFor(raw['limit_window_seconds']),
      usedPercent: used,
      resetsAt: parseResetTimestamp(raw['reset_at']),
    );
  }

  /// Names a window by how long it actually is.
  ///
  /// Falls back to the neutral "Limit" rather than guessing: a window whose
  /// duration the server did not send is one this build knows nothing about,
  /// and a made-up "5h" beside a real percentage would be read as measured.
  static String _labelFor(Object? seconds) {
    final value = seconds is num && seconds.isFinite && seconds > 0
        ? seconds.round()
        : null;
    if (value == null) return 'Limit';
    final hours = value ~/ 3600;
    if (hours < 1) return '${value ~/ 60}m';
    if (hours < 24) return '${hours}h';
    final days = hours ~/ 24;
    return days == 7 ? kWeeklyWindowLabel : '${days}d';
  }
}
