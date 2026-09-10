import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/harness_cli_runner.dart';
import 'grid_surface.dart';

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

  /// Value equality, so re-reading the file is free to do often.
  ///
  /// [GridSessionStore] is a [ValueNotifier], which skips the notification when
  /// the new value equals the old one — and every listener on it either re-asks
  /// the Grid API or rebuilds a pane. Without this, the watcher below would wake
  /// all of them every time the CLI touched the file, including the token
  /// refreshes that change nothing this app can see.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GridSession &&
          other.token == token &&
          other.apiBaseUrl == apiBaseUrl &&
          other.email == email;

  @override
  int get hashCode => Object.hash(token, apiBaseUrl, email);
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
  GridSessionStore({
    File? file,
    HarnessCliRunner? runner,
    // A compile-time const in the app, which makes the shipped build's own
    // behaviour — a sign-in that never happens — unreachable from a test run,
    // where it is always true. Passed in so that case can be asserted, exactly
    // as `GridSelectionStore` takes it.
    @visibleForTesting this.gridSurface = kGridSurfaceEnabled,
  }) : _file = file ?? File(defaultCredentialsPath()),
       _runner = runner ?? HarnessCliRunner(),
       super(null);

  final File _file;
  final HarnessCliRunner _runner;

  /// See the constructor: [kGridSurfaceEnabled], and only a test passes another.
  final bool gridSurface;

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
    // Cheap when it is already attached, and the only chance to attach when the
    // app started before `~/.grid` existed.
    _attachWatch();
  }

  /// Re-reads after something outside this app may have changed it — a
  /// `grid login` in a terminal, a `grid logout`, or our own [signIn].
  Future<void> refresh() => load();

  /// Keeps reading the credential file for as long as the app runs.
  ///
  /// The file is written by a CLI this app does not drive: `grid login` and
  /// `grid logout` in a terminal both replace it, `harness grid login` run
  /// anywhere else does, and the serve loop rewrites it when a per-grid token
  /// refreshes. Until this existed nothing ever re-read it — [refresh] had no
  /// callers at all — so the app held the session it happened to read at launch
  /// and went on serving the previous account's grids for the life of the
  /// process, with nothing on screen that could fix it.
  ///
  /// The parent directory is watched rather than the file: `remote/credentials`
  /// writes through a temp file and `os.replace`s it into place, and a watch on
  /// an inode that gets replaced stops hearing about the name. Idempotent, and
  /// safe to call before `~/.grid` exists — [load] tries again each time, and
  /// the app's own [signIn] creates the directory on its way past.
  void watchForChanges() {
    _watching = true;
    _attachWatch();
  }

  bool _watching = false;
  StreamSubscription<FileSystemEvent>? _watch;
  Timer? _settle;

  void _attachWatch() {
    if (!_watching || _watch != null) return;
    final directory = _file.parent;
    try {
      if (!directory.existsSync()) return;
      _watch = directory.watch().listen(
        _onFileEvent,
        // A watch that has died is worse than none: it reports nothing and
        // looks alive. Drop it, and let the next [load] attach a new one.
        onError: (Object _) => _detachWatch(),
        onDone: _detachWatch,
      );
    } on Object {
      // No watch on this platform, or the directory went away between the two
      // lines above. The explicit paths — [signIn], [signOut], [refresh] —
      // still work; only changes made elsewhere go unnoticed.
      _detachWatch();
    }
  }

  void _detachWatch() {
    _watch?.cancel();
    _watch = null;
  }

  void _onFileEvent(FileSystemEvent event) {
    if (!_isOurs(event.path) &&
        !(event is FileSystemMoveEvent && _isOurs(event.destination ?? ''))) {
      return;
    }
    // One write lands as several events — the temp file, the replace, and the
    // chmod after it — and a login writes the file twice. Read once, after it
    // has stopped moving.
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 250), load);
  }

  /// Whether [path] is the credential file or the temp file it is written
  /// through: `credentials.toml.tmp`, which `os.replace` renames over it.
  bool _isOurs(String path) =>
      path.split(Platform.pathSeparator).last.startsWith(
        _file.uri.pathSegments.last,
      );

  @override
  void dispose() {
    _watching = false;
    _settle?.cancel();
    _detachWatch();
    super.dispose();
  }

  /// Makes sure this computer has a Grid session **for [account]**, signing in
  /// through `harness grid login --json` when it has none — or when the one it
  /// has belongs to somebody else.
  ///
  /// "Make sure", not "run the login": the check is HERE rather than at each
  /// caller because every run mints a fresh 365-day session and revokes
  /// nothing, and there are two callers — the bootstrap and the pane's button —
  /// that can race each other on a fresh machine. A button pressed a moment
  /// after the bootstrap won its race would otherwise mint a second session for
  /// a machine that already had one, which is the pile-up this whole design
  /// exists to avoid.
  ///
  /// [account] is the Harness address this machine is signed in as. A Grid
  /// session under any other address is **replaced**, because `harness logout`
  /// deliberately leaves `~/.grid/credentials.toml` alone (there is no cascade
  /// between the two sign-ins, by design) — so signing out and back in as
  /// somebody else otherwise left this app serving the previous person's grids
  /// forever, with nothing on screen that could fix it.
  ///
  /// Null means "whoever is here is fine", which is the old behaviour and what
  /// a caller that does not know the address passes. It is NOT a licence to
  /// re-mint: a session that matches is still left exactly alone. Replacing is
  /// the one case that earns a fresh 365-day session, because the alternative
  /// is an app that shows the wrong account's grids.
  ///
  /// Returns null on success and a sentence to show otherwise. Nothing throws:
  /// every caller is a button, and none of them has anywhere to put an
  /// exception.
  ///
  /// The CLI's own refusals already name their way forward ("update the grid
  /// CLI", "run harness login again"), so they are passed through verbatim
  /// rather than re-worded here — this app is not the second place that has an
  /// opinion about why a sign-in did not happen.
  Future<String?> signIn({String? account}) async {
    // ⚠️ A build that hides Grid never MINTS one. This is called unprompted on
    // every bootstrap (`AppNotifier._ensureGridSession`), and every call that
    // gets through puts a fresh 365-day session on the person's Grid account
    // and revokes nothing — with `grid logout --everywhere`, all-or-nothing
    // across every machine, as the only way back. In a build with no Settings ▸
    // Grid that is a credential the owner can neither see, explain, nor undo
    // from inside the app, minted for a feature they were never shown.
    //
    // [load] is deliberately NOT gated with it: a session already on disk was
    // written by `grid login` in a terminal and directs nothing on its own,
    // and nothing in a shipped build ever draws or spends it.
    if (!gridSurface) return 'This build does not include Grid';
    // Re-read first: something may have signed in since we last looked — the
    // bootstrap, a `grid login` in a terminal, or the other caller.
    await load();
    if (signedIn && !_belongsToSomebodyElse(account)) return null;
    final ProcessResult result;
    try {
      // ⚠️ No `--force`. It is not a Grid flag: `harness grid login` hands it to
      // the HARNESS sign-in, where it means "do the whole SSO again even though
      // this computer is already signed in" — that path stops the running
      // daemon first (`if (force) await stopDaemonProcess()`) and then waits on
      // a browser round trip this app has no window to complete.
      //
      // It is also not needed. Measured against a live session: plain
      // `harness grid login --json` exits 0 and REPLACES the token on disk, so
      // the handoff already overwrites whoever was there.
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

  /// Signs this computer out of Grid — `harness grid logout --json`.
  ///
  /// Returns null when there was nothing to do or it worked, and a sentence to
  /// show otherwise. Nothing throws, for the same reason [signIn] does not.
  ///
  /// **The caller must not block a Harness sign-out on this.** Refusing to sign
  /// somebody out of Harness because a Grid command failed would trap them in
  /// an account they asked to leave. The sentence is for saying what is still
  /// on the machine, not for stopping anything.
  ///
  /// ⚠️ `grid logout` **stops whatever engine this machine is serving** before
  /// it deletes anything — its own `--force` exists for the case where that
  /// teardown fails. That engine is detached and normally outlives the app, so
  /// signing out ends a share the user deliberately left running. Deliberate:
  /// a credential that outlives the sign-out is worse, and the alternative was
  /// leaving a live 365-day token on a machine somebody just signed out of.
  ///
  /// **This machine only.** `--everywhere` would sign out every other machine
  /// on the account and is never passed here.
  Future<String?> signOut() async {
    await load();
    // Nothing to delete: say so by doing nothing, rather than running a command
    // whose refusal would then need explaining.
    if (!signedIn) return null;
    final ProcessResult result;
    try {
      result = await _runner.run(['grid', 'logout', '--json']);
    } on Object catch (error) {
      return 'Could not run the harness CLI to sign out of Grid: $error';
    }
    // The file is the only thing that decides whether we still have a session,
    // whatever the command said about itself.
    await load();
    if (!signedIn) return null;
    final said = '${result.stderr}'.trim();
    return 'This computer is still signed in to Grid'
        '${said.isEmpty ? '' : ' — $said'}. '
        'Run `harness grid logout` in a terminal to clear it.';
  }

  /// Whether the session on disk is somebody other than [account].
  ///
  /// False whenever either address is unknown — the same rule Settings ▸ Grid
  /// draws its mismatch warning by. "We have not asked yet" must never be
  /// treated as "they differ": that reading would re-mint a session on a
  /// machine whose profile call was merely slow, which is the pile-up this
  /// class exists to prevent.
  bool _belongsToSomebodyElse(String? account) {
    final harness = account?.trim();
    final grid = value?.email?.trim();
    if (harness == null || harness.isEmpty) return false;
    if (grid == null || grid.isEmpty) return false;
    return grid.toLowerCase() != harness.toLowerCase();
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
