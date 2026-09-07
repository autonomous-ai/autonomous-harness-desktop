/// Turning a WS frame into one log line, with credentials removed.
///
/// This exists because the frames worth logging are exactly the ones that carry
/// secrets: `agent_create`'s payload holds `grid.apiKey`, a live relay key
/// minted for that launch (see `GridAgentOverride.toJson`). A blind
/// `payload.toString()` would write it to `~/.harness/logs`, where it long
/// outlives the short-lived key it was supposed to be.
///
/// The rule is a DENYLIST on key names rather than an allowlist on purpose. An
/// allowlist would silently drop the next field somebody adds — and the whole
/// value of this log is seeing fields nobody thought to anticipate, which is how
/// the missing `grid` on a created agent would have been spotted. The cost is
/// that a new secret must be named here; [_secretKey] is deliberately broad for
/// that reason, and [redactValue] is exported so a test can pin it.
library;

/// Key names whose value must never reach the log. Broad on purpose: matching a
/// field that was not secret costs one unreadable line, missing one that was
/// costs a credential on disk.
final RegExp _secretKey = RegExp(
  r'key|token|secret|password|passphrase|credential|auth|bearer|cookie|session',
  caseSensitive: false,
);

/// Values longer than this are clipped — a log line is read by a person, and a
/// base64 blob buries the fields either side of it.
const int _maxValue = 120;

/// One frame payload as a log line: `{engine: codex, grid: {model: X, apiKey: <redacted>}}`.
///
/// The cap is generous because of what these lines are for. An `agent_create`
/// reply carries a whole `Agent` — id, name, engine, session, status, cwd — and
/// `grid` sits near the end of it. A tighter cap reads better and would have cut
/// off the one field somebody is reading the log to find. Individual values are
/// still clipped at [_maxValue], so one blob cannot eat the budget.
String summariseForLog(Object? value, {int maxLength = 1200}) {
  final text = redactValue(value);
  return text.length <= maxLength
      ? text
      : '${text.substring(0, maxLength)}…';
}

/// [value] rendered for a log, with any entry whose KEY looks secret replaced.
///
/// Recurses into maps and lists so a secret nested under `grid` is caught too —
/// which is exactly where the one this was written for lives.
String redactValue(Object? value) {
  if (value == null) return 'null';
  if (value is Map) {
    final parts = <String>[];
    for (final entry in value.entries) {
      final key = '${entry.key}';
      parts.add(
        _secretKey.hasMatch(key)
            ? '$key: <redacted>'
            : '$key: ${redactValue(entry.value)}',
      );
    }
    return '{${parts.join(', ')}}';
  }
  if (value is List) {
    // Length, not contents: a list in a frame is a batch (agents, models,
    // frames) and printing it whole turns one line into a page.
    return '[${value.length} item${value.length == 1 ? '' : 's'}]';
  }
  final text = '$value';
  return text.length <= _maxValue ? text : '${text.substring(0, _maxValue)}…';
}
