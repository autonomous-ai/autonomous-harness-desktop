import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/harness_cli_runner.dart';

/// The Grid account this computer is signed in to.
///
/// Read from the **Grid CLI's own** credential file, `~/.grid/credentials.toml`
/// — the file `grid login` writes and `grid logout` deletes. This app never
/// writes it and holds no Grid credential of its own: there is exactly one Grid
/// sign-in per machine, and a second copy of it here is a second thing to
/// expire, to leak, and to disagree with the CLI about.
///
/// Signing in is `harness grid login`, which hands the Harness session the app
/// already has to `grid login --harness` over that child's stdin — no browser,
/// and the account token never reaches an argv every user on the machine can
/// read. See [GridSessionStore.signIn].
@immutable
class GridSession {
  const GridSession({
    required this.token,
    required this.apiBaseUrl,
    this.email,
  });

  /// The account session token, sent as `Authorization: Bearer …`. Per-grid
  /// tokens are a different thing entirely and stay with the CLI.
  final String token;

  /// The control plane the CLI is pointed at. Read rather than assumed: a
  /// developer whose `grid` talks to staging would otherwise have this app send
  /// their staging token to production and get an unexplained 401.
  final String apiBaseUrl;

  /// Who the CLI says is signed in. Shown, never sent anywhere.
  final String? email;
}

/// Where the Grid session comes from, and how to get one.
///
/// A [ValueNotifier] singleton like `gridSelectionStore`, loaded before the
/// first frame by `loadPersistedSettings`: the Grid screen, the status rail and
/// the share sheet all need it and have no common ancestor short of
/// `MaterialApp`. It is re-read rather than cached forever, so a `grid login`
/// or `grid logout` run in a terminal is picked up by [refresh] instead of
/// leaving the app confidently wrong.
class GridSessionStore extends ValueNotifier<GridSession?> {
  GridSessionStore({File? file, HarnessCliRunner? runner})
    : _file = file ?? File(defaultCredentialsPath()),
      _runner = runner ?? HarnessCliRunner(),
      super(null);

  final File _file;
  final HarnessCliRunner _runner;

  /// True once [load] has run, whatever it found. Without it "still reading"
  /// and "signed out" render the same, and the Grid pane would offer a sign-in
  /// button for the frame before the file is read on every launch.
  bool loaded = false;

  bool get signedIn => value != null;

  static String defaultCredentialsPath({Map<String, String>? environment}) {
    final home = (environment ?? Platform.environment)['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError('Could not resolve the current user home directory');
    }
    return '$home/.grid/credentials.toml';
  }

  /// Reads the credential file. Never throws: a missing, unreadable or
  /// half-written file is "signed out", which is a state the UI is built to
  /// show, not a failure to report.
  Future<void> load() async {
    GridSession? next;
    try {
      if (await _file.exists()) {
        next = parseGridCredentials(await _file.readAsString());
      }
    } on Object {
      // Unreadable or mid-write. Signed out until the next look.
    }
    loaded = true;
    value = next;
  }

  /// Re-reads after something outside this app may have changed it — a
  /// `grid login` in a terminal, a `grid logout`, or our own [signIn].
  Future<void> refresh() => load();

  /// Makes sure this computer has a Grid session, signing in through
  /// `harness grid login --json` when it has none.
  ///
  /// "Make sure", not "run the login": the check is HERE rather than at each
  /// caller because every run mints a fresh 365-day session and revokes
  /// nothing, and there are two callers — the bootstrap and the pane's button —
  /// that can race each other on a fresh machine. A button pressed a moment
  /// after the bootstrap won its race would otherwise mint a second session for
  /// a machine that already had one, which is the pile-up this whole design
  /// exists to avoid.
  ///
  /// Returns null on success and a sentence to show otherwise. Nothing throws:
  /// every caller is a button, and none of them has anywhere to put an
  /// exception.
  ///
  /// The CLI's own refusals already name their way forward ("update the grid
  /// CLI", "run harness login again"), so they are passed through verbatim
  /// rather than re-worded here — this app is not the second place that has an
  /// opinion about why a sign-in did not happen.
  Future<String?> signIn() async {
    // Re-read first: something may have signed in since we last looked — the
    // bootstrap, a `grid login` in a terminal, or the other caller.
    await load();
    if (signedIn) return null;
    final ProcessResult result;
    try {
      result = await _runner.run(['grid', 'login', '--json']);
    } on Object catch (error) {
      return 'Could not run the harness CLI: $error';
    }
    final failure = gridLoginFailure(
      exitCode: result.exitCode,
      stdout: '${result.stdout}',
      stderr: '${result.stderr}',
    );
    // Re-read either way: a sign-in that half-succeeded still leaves a session
    // on disk, and the file is the only thing that decides whether we have one.
    await load();
    if (failure != null) return failure;
    return signedIn
        ? null
        : 'The sign-in reported success but left no Grid session on this '
              'computer. Run `harness grid login` in a terminal to see why.';
  }
}

/// The message to show for a finished `harness grid login --json`, or null when
/// it worked.
///
/// The CLI writes NDJSON on stdout and ends with exactly one `result` line, so
/// the LAST parseable line is the answer — the sign-in it chains emits its own
/// lines before that one. Its refusals carry both a `message` (this command's
/// classification) and a `detail` (what `grid` itself said on stderr); the
/// detail is the more useful of the two when it is there, because it comes from
/// the tool that actually refused.
@visibleForTesting
String? gridLoginFailure({
  required int exitCode,
  required String stdout,
  required String stderr,
}) {
  Map<String, Object?>? result;
  for (final line in const LineSplitter().convert(stdout)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map && decoded['type'] == 'result') {
        result = Map<String, Object?>.from(decoded);
      }
    } on FormatException {
      // Not every line is ours to read — the chained sign-in writes its own.
    }
  }
  if (result != null) {
    if (result['status'] == 'success') return null;
    final detail = _text(result['detail']) ?? _text(result['message']);
    if (detail != null) return detail;
  }
  if (exitCode == 0) return null;
  final said = stderr.trim();
  return said.isNotEmpty ? said : 'The Grid sign-in failed (exit $exitCode).';
}

String? _text(Object? value) {
  final text = value is String ? value.trim() : '';
  return text.isEmpty ? null : text;
}

/// The session inside a `credentials.toml`, or null when it holds none.
///
/// A hand-rolled read of three top-level keys rather than a TOML dependency:
/// this is one file this app does not own, written by
/// `remote/credentials.py`'s `tomli_w.dumps`, and the alternative is a parser
/// that must stay right about a whole format to answer one question. Scanning
/// stops at the first table header — everything below `[[networks]]` is
/// per-grid, and `name` means something different down there.
@visibleForTesting
GridSession? parseGridCredentials(String toml) {
  String? token;
  String? apiUrl;
  String? email;
  for (final line in const LineSplitter().convert(toml)) {
    final trimmed = line.trim();
    if (trimmed.startsWith('[')) break;
    token ??= _topLevelString(trimmed, 'session_token');
    apiUrl ??= _topLevelString(trimmed, 'api_url');
    email ??= _topLevelString(trimmed, 'email');
  }
  if (token == null || token.isEmpty) return null;
  return GridSession(
    token: token,
    // The CLI's own default when the key is absent, so an older credential file
    // written before `api_url` existed still reaches the right host.
    apiBaseUrl: (apiUrl == null || apiUrl.isEmpty) ? kGridApiBaseUrl : apiUrl,
    email: email,
  );
}

/// `key = "value"` on one already-trimmed top-level line.
///
/// Only the basic-string form, which is all `tomli_w` emits for these three: a
/// JWT, a URL and an address carry nothing TOML escapes, so a value with a
/// backslash in it means the file is not what we think it is and reading it as
/// literal text would be the wrong kind of confident.
String? _topLevelString(String line, String key) {
  final match = RegExp('^${RegExp.escape(key)}\\s*=\\s*"([^"\\\\]*)"\$')
      .firstMatch(line);
  return match?.group(1);
}

/// Where the Grid control plane lives when the CLI has not said otherwise.
const kGridApiBaseUrl = 'https://api-grid.autonomous.ai';

/// The one instance the app reads. Loaded by `loadPersistedSettings()`.
final GridSessionStore gridSessionStore = GridSessionStore();
