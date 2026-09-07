import 'app_log.dart';
import 'cli_log.dart';
import 'log_file.dart';

/// Base names of the two per-day files under `~/.harness/logs`.
const String kAppLogBase = 'app';
const String kCliLogBase = 'cli';

/// Point [appLog] and [cliLog] at real files under `~/.harness/logs`.
///
/// Called once from `main()`. Nothing else calls it, which is what keeps the
/// suite honest: both sinks default to their no-op, so `flutter test` cannot
/// write into a real Harness home no matter which code path it exercises — the
/// same rule analytics follows.
///
/// Deliberately not `async`: the first lines this app writes are the ones about
/// starting up, and awaiting a directory probe here would lose them.
void installFileLogs() {
  final directory = DailyLogFile.defaultDirectory;
  appLog = FileAppLog(DailyLogFile(directory, kAppLogBase));
  cliLog = FileCliLog(DailyLogFile(directory, kCliLogBase));
}
