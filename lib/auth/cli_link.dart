import 'dart:io';

import '../core/harness_cli_runner.dart';

/// Runs `harness link import <token>` through the app-owned CLI runtime. This
/// is the app's one way to trigger a machine link without opening a terminal —
/// the token itself, and the trust it establishes, live entirely in the CLI;
/// the app never holds any of it.
class CliLinkImportResult {
  /// Null on success.
  final String? error;

  /// The machineId the CLI actually linked — parsed from its own success line, since a token
  /// pasted on one machine's screen could (by mistake, or by design) target a different one. Null
  /// if [error] is set, or if the CLI's output didn't match the expected shape.
  final String? linkedMachineId;

  const CliLinkImportResult({this.error, this.linkedMachineId});
}

/// Result of `harness link create` — a fresh token for ANOTHER machine's `link import` to consume.
class CliLinkCreateResult {
  /// Null on success.
  final String? error;
  final String? token;
  final String? fingerprint;

  const CliLinkCreateResult({this.error, this.token, this.fingerprint});
}

/// One row of `harness link list`.
class LinkedMachine {
  final String machineId;
  final String fingerprint;

  /// As printed by the CLI: `YYYY-MM-DD HH:MM`.
  final String linkedAt;

  const LinkedMachine({
    required this.machineId,
    required this.fingerprint,
    required this.linkedAt,
  });
}

class CliLinkListResult {
  /// Null on success (an empty list is success with zero rows, not an error).
  final String? error;
  final List<LinkedMachine> machines;

  const CliLinkListResult({this.error, this.machines = const []});
}

class CliLink {
  final HarnessCliRunner _runner;

  CliLink({HarnessCliRunner? runner}) : _runner = runner ?? HarnessCliRunner();
  static final _linkedPattern = RegExp(r'Linked machine (\S+)');
  static final _tokenPattern = RegExp(
    r'Machine-link token \(valid for 7 days\):\s*\n\s*(\S+)',
  );
  static final _fingerprintPattern = RegExp(r'fingerprint\s+(\S+)');
  static final _listRowPattern = RegExp(
    r'^\s*\d+\.\s+(\S+)\s+(\S+)\s+\(linked\s+([\d-]+\s[\d:]+)\)',
    multiLine: true,
  );

  Future<CliLinkImportResult> import(String token) async {
    final response = await _run(['link', 'import', token]);
    if (response.error != null) {
      return CliLinkImportResult(error: response.error);
    }
    final result = response.result!;
    final stdoutText = (result.stdout as String).trim();
    if (result.exitCode == 0) {
      return CliLinkImportResult(
        linkedMachineId: _linkedPattern.firstMatch(stdoutText)?.group(1),
      );
    }
    return CliLinkImportResult(
      error: _errorMessage(result, stdoutText, 'harness link import'),
    );
  }

  /// Mints a fresh 7-day token for THIS machine, for another machine's `link import` to consume.
  Future<CliLinkCreateResult> create() async {
    final response = await _run(['link', 'create']);
    if (response.error != null) {
      return CliLinkCreateResult(error: response.error);
    }
    final result = response.result!;
    final stdoutText = (result.stdout as String).trim();
    if (result.exitCode == 0) {
      return CliLinkCreateResult(
        token: _tokenPattern.firstMatch(stdoutText)?.group(1),
        fingerprint: _fingerprintPattern.firstMatch(stdoutText)?.group(1),
      );
    }
    return CliLinkCreateResult(
      error: _errorMessage(result, stdoutText, 'harness link create'),
    );
  }

  /// Machines this one currently trusts (CLI-to-CLI, not the browser-pairing list).
  Future<CliLinkListResult> list() async {
    final response = await _run(['link', 'list']);
    if (response.error != null) {
      return CliLinkListResult(error: response.error);
    }
    final result = response.result!;
    final stdoutText = (result.stdout as String).trim();
    if (result.exitCode != 0) {
      return CliLinkListResult(
        error: _errorMessage(result, stdoutText, 'harness link list'),
      );
    }
    return CliLinkListResult(
      machines: [
        for (final m in _listRowPattern.allMatches(stdoutText))
          LinkedMachine(
            machineId: m.group(1)!,
            fingerprint: m.group(2)!,
            linkedAt: m.group(3)!,
          ),
      ],
    );
  }

  /// Removes a linked machine's trust pin. Null on success.
  Future<String?> unlink(String machineId) async {
    final response = await _run(['link', 'unlink', machineId]);
    if (response.error != null) return response.error;
    final result = response.result!;
    if (result.exitCode == 0) return null;
    return _errorMessage(
      result,
      (result.stdout as String).trim(),
      'harness link unlink',
    );
  }

  String _errorMessage(
    ProcessResult result,
    String stdoutText,
    String command,
  ) {
    final stderrText = (result.stderr as String).trim();
    final message = stderrText.isNotEmpty ? stderrText : stdoutText;
    return message.isEmpty
        ? '$command failed (exit ${result.exitCode})'
        : message;
  }

  Future<_CliInvocation> _run(List<String> arguments) async {
    try {
      return _CliInvocation(result: await _runner.run(arguments));
    } on ProcessException catch (error) {
      return _CliInvocation(
        error: 'Could not run the Harness CLI: ${error.message}',
      );
    }
  }
}

class _CliInvocation {
  final ProcessResult? result;
  final String? error;

  const _CliInvocation({this.result, this.error})
    : assert((result == null) != (error == null));
}
