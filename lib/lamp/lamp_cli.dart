import 'dart:async';
import 'dart:convert';

import '../core/harness_cli_runner.dart';
import '../core/test_run.dart';

class LampCliException implements Exception {
  const LampCliException(this.code, this.message);
  final String code;
  final String message;
  bool get unsupported =>
      const {'NOT_FOUND', 'UNSUPPORTED', 'UNKNOWN_COMMAND'}.contains(code);
  @override
  String toString() => message;
}

/// The CLI owns credentials and lamp trust. Pair codes remain in memory only.
class LampCli {
  LampCli({HarnessCliRunner? runner}) : _runner = runner ?? HarnessCliRunner();
  final HarnessCliRunner _runner;

  Future<Map<String, dynamic>> status() => command('status');
  Future<Map<String, dynamic>> list() => command('list');
  Future<Map<String, dynamic>> pairStatus() => command('pair-status');
  Future<Map<String, dynamic>> pair({bool replace = false}) =>
      command('pair', arguments: [if (replace) '--replace']);
  Future<Map<String, dynamic>> cancel() => command('cancel');
  Future<Map<String, dynamic>> revoke(String id) =>
      command('revoke', arguments: [id]);

  Future<Map<String, dynamic>> command(
    String operation, {
    List<String> arguments = const [],
  }) async {
    if (kUnderTest) {
      throw const LampCliException(
        'TEST_DISABLED',
        'Inject a fake LampCli in tests.',
      );
    }
    // start logs lifecycle only; run would persist the secret code in stdout.
    final process = await _runner.start([
      'lamp',
      operation,
      ...arguments,
      '--json',
    ]);
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    final int exitCode;
    try {
      exitCode = await process.exitCode.timeout(const Duration(seconds: 35));
    } on TimeoutException {
      process.kill();
      // A timed-out mutation may have succeeded. Read state before retrying it.
      throw const LampCliException(
        'TIMEOUT',
        'The command timed out. Refresh the lamp status before trying again.',
      );
    }
    final output = await stdout;
    final errorOutput = await stderr;
    Map<String, dynamic>? result;
    for (final line in const LineSplitter().convert(output)) {
      try {
        final value = jsonDecode(line);
        if (value is Map<String, dynamic>) result = value;
      } on FormatException {
        /* Ignore CLI startup progress. */
      }
    }
    final error = result?['error'];
    if (error is Map) {
      throw LampCliException(
        error['code']?.toString() ?? 'FAILED',
        error['message']?.toString() ?? 'The lamp command failed.',
      );
    }
    if (exitCode != 0 || result == null) {
      final unsupported = RegExp(
        r'unknown command|unknown subcommand|unrecognized command',
        caseSensitive: false,
      ).hasMatch('$output\n$errorOutput');
      throw LampCliException(
        unsupported ? 'UNKNOWN_COMMAND' : 'FAILED',
        unsupported ? 'This Harness CLI does not support lamp devices.' : 'The lamp command failed. Check that Harness is signed in and running.',
      );
    }
    return result;
  }
}
