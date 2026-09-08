import 'dart:async';
import 'dart:convert';

import '../core/harness_cli_runner.dart';
import '../core/test_run.dart';

class AutonomousDeviceCliException implements Exception {
  const AutonomousDeviceCliException(this.code, this.message);
  final String code;
  final String message;
  bool get unsupported =>
      const {'NOT_FOUND', 'UNSUPPORTED', 'UNKNOWN_COMMAND'}.contains(code);
  @override
  String toString() => message;
}

/// The CLI owns credentials and Autonomous device trust. Pair codes remain in memory only.
class AutonomousDeviceCli {
  AutonomousDeviceCli({HarnessCliRunner? runner})
    : _runner = runner ?? HarnessCliRunner();
  final HarnessCliRunner _runner;

  Future<Map<String, dynamic>> status() => command('status');
  Future<Map<String, dynamic>> list() => command('list');
  Future<Map<String, dynamic>> pairStatus() => command('pair-status');
  Future<Map<String, dynamic>> listen({bool replace = false}) =>
      command('listen', arguments: [if (replace) '--replace']);
  Future<Map<String, dynamic>> pair({
    required String code,
    required String pairId,
    bool replace = false,
  }) async {
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(code) || pairId.isEmpty) {
      throw const AutonomousDeviceCliException(
        'BAD_REQUEST',
        'Enter the six-character code shown on your Autonomous device.',
      );
    }
    return command(
      'pair',
      arguments: [
        '--code-stdin',
        '--pair-id',
        pairId,
        if (replace) '--replace',
      ],
      secretStdin: code,
    );
  }

  Future<Map<String, dynamic>> cancel() => command('cancel');
  Future<Map<String, dynamic>> revoke(String id) =>
      command('revoke', arguments: [id]);

  Future<Map<String, dynamic>> command(
    String operation, {
    List<String> arguments = const [],
    String? secretStdin,
  }) async {
    if (kUnderTest) {
      throw const AutonomousDeviceCliException(
        'TEST_DISABLED',
        'Inject a fake AutonomousDeviceCli in tests.',
      );
    }
    // start logs lifecycle only; run would persist the secret code in stdout.
    final process = await _runner.start([
      'autonomous-device',
      operation,
      ...arguments,
      '--json',
    ]);
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    if (secretStdin != null) process.stdin.writeln(secretStdin);
    await process.stdin.close();
    final int exitCode;
    try {
      exitCode = await process.exitCode.timeout(const Duration(seconds: 35));
    } on TimeoutException {
      process.kill();
      // A timed-out mutation may have succeeded. Read state before retrying it.
      throw const AutonomousDeviceCliException(
        'TIMEOUT',
        'The command timed out. Refresh the Autonomous device status before trying again.',
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
      throw AutonomousDeviceCliException(
        error['code']?.toString() ?? 'FAILED',
        error['message']?.toString() ?? 'The Autonomous device command failed.',
      );
    }
    if (exitCode != 0 || result == null) {
      final unsupported = RegExp(
        r'unknown command|unknown subcommand|unrecognized command',
        caseSensitive: false,
      ).hasMatch('$output\n$errorOutput');
      throw AutonomousDeviceCliException(
        unsupported ? 'UNKNOWN_COMMAND' : 'FAILED',
        unsupported ? 'This Harness CLI does not support Autonomous devices.' : 'The Autonomous device command failed. Check that Harness is signed in and running.',
      );
    }
    return result;
  }
}
