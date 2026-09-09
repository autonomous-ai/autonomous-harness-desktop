import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/harness_cli_runner.dart';
import 'package:harness/grid/grid_api_client.dart';
import 'package:harness/grid/grid_networks_controller.dart';
import 'package:harness/grid/grid_session.dart';

import 'support/fake_grid_api.dart';

/// A runner that answers `harness grid login` from a script instead of running
/// a CLI. `HarnessCliRunner.run` is the only method these tests reach.
class FakeCliRunner implements HarnessCliRunner {
  FakeCliRunner(this.answer, {this.onRun});

  ProcessResult answer;
  final void Function(List<String> arguments)? onRun;
  final List<List<String>> calls = [];

  @override
  Future<ProcessResult> run(List<String> arguments) async {
    calls.add(arguments);
    onRun?.call(arguments);
    return answer;
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} is not used here');
}

ProcessResult exited(int code, {String stdout = '', String stderr = ''}) =>
    ProcessResult(1, code, stdout, stderr);

/// A credentials.toml the way `remote/credentials.py` writes one: top-level
/// keys first, then one table per grid.
const _realShape = '''
session_token = "session-abc"
api_url = "https://api-grid.autonomous.ai"
google_sub = "10721723682948661189"
email = "someone@example.test"
name = "Someone"

[[networks]]
network_id = "grid-1"
name = "macOS"
network_type = "os-community"
''';

/// The same file after somebody else signs in on this machine. A different
/// token above all — that is what the grid list is fetched with.
const _otherAccount = '''
session_token = "session-xyz"
api_url = "https://api-grid.autonomous.ai"
email = "nobody@example.test"

[[networks]]
network_id = "grid-2"
name = "bubu1"
network_type = "domain-restricted"
''';

void main() {
  late Directory scratch;

  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('harness-grid-session-');
  });

  tearDown(() async {
    if (await scratch.exists()) await scratch.delete(recursive: true);
  });

  // --- reading the CLI's file ---------------------------------------------

  test('reads the session out of a real credentials.toml', () {
    final session = parseGridCredentials(_realShape);

    expect(session, isNotNull);
    expect(session!.token, 'session-abc');
    expect(session.apiBaseUrl, 'https://api-grid.autonomous.ai');
    expect(session.email, 'someone@example.test');
  });

  test('stops at the first table, so a grid\'s name is never the user\'s', () {
    final session = parseGridCredentials('''
session_token = "session-abc"
name = "The Account"

[[networks]]
email = "not-the-user@example.test"
name = "A Grid"
''');

    expect(
      session!.email,
      isNull,
      reason: 'the address below [[networks]] is not the account',
    );
  });

  test('an older file with no api_url still reaches the right host', () {
    final session = parseGridCredentials('session_token = "session-abc"\n');

    expect(session!.apiBaseUrl, kGridApiBaseUrl);
  });

  test('a file with no session, or a broken one, reads as signed out', () {
    expect(parseGridCredentials(''), isNull);
    expect(parseGridCredentials('session_token = ""\n'), isNull);
    expect(parseGridCredentials('not toml at all {{{'), isNull);
    // The key exists but below a table: that is a grid's field, not the account.
    expect(
      parseGridCredentials('[[networks]]\nsession_token = "nope"\n'),
      isNull,
    );
  });

  test('a missing file is signed out, not a thrown launch', () async {
    final store = GridSessionStore(
      file: File('${scratch.path}/absent.toml'),
      runner: FakeCliRunner(exited(0)),
    );

    await store.load();

    expect(store.signedIn, isFalse);
    expect(store.loaded, isTrue, reason: '"read it" and "found none" differ');
  });

  test('load picks up a session written while the app was running', () async {
    final file = File('${scratch.path}/credentials.toml');
    final store = GridSessionStore(
      file: file,
      runner: FakeCliRunner(exited(0)),
    );
    await store.load();
    expect(store.signedIn, isFalse);

    file.writeAsStringSync(_realShape);
    await store.refresh();

    expect(store.value?.token, 'session-abc');
  });

  // --- signing in ----------------------------------------------------------

  test(
    'sign-in runs `harness grid login --json` and re-reads the file',
    () async {
      final file = File('${scratch.path}/credentials.toml');
      final runner = FakeCliRunner(
        exited(
          0,
          stdout:
              '{"type":"result","status":"success","alreadySignedIn":true}\n',
        ),
        // The CLI is what writes the file; the fake stands in for that side effect.
        onRun: (_) => file.writeAsStringSync(_realShape),
      );
      final store = GridSessionStore(file: file, runner: runner);

      final failure = await store.signIn();

      expect(failure, isNull);
      expect(runner.calls.single, ['grid', 'login', '--json']);
      expect(store.value?.token, 'session-abc');
    },
  );

  test('a refusal is passed through in the CLI\'s own words', () {
    final message = gridLoginFailure(
      exitCode: 1,
      stdout:
          '{"type":"result","status":"error","code":"GRID_CLI_OUTDATED",'
          '"message":"Your `grid` CLI is too old.",'
          '"detail":"grid: error: unrecognized arguments: --harness"}\n',
      stderr: '',
    );

    // The child's own sentence wins over our classification of it: it comes
    // from the tool that actually refused.
    expect(message, 'grid: error: unrecognized arguments: --harness');
  });

  test('the result line is read past the sign-in lines before it', () {
    final message = gridLoginFailure(
      exitCode: 0,
      stdout:
          '{"type":"authorize_url","url":"https://example.test/x"}\n'
          'not json at all\n'
          '{"type":"result","status":"success"}\n',
      stderr: '',
    );

    expect(message, isNull);
  });

  test('a crash with no result line still says something', () {
    expect(gridLoginFailure(exitCode: 3, stdout: '', stderr: 'boom\n'), 'boom');
    expect(
      gridLoginFailure(exitCode: 3, stdout: '', stderr: ''),
      contains('exit 3'),
    );
  });

  test('success that leaves no session is reported, not celebrated', () async {
    final store = GridSessionStore(
      file: File('${scratch.path}/credentials.toml'),
      runner: FakeCliRunner(
        exited(0, stdout: '{"type":"result","status":"success"}\n'),
      ),
    );

    final failure = await store.signIn();

    expect(failure, isNotNull);
    expect(store.signedIn, isFalse);
  });

  // --- signing in exactly once ---------------------------------------------

  test('signIn over a live session runs no CLI at all', () async {
    final file = File('${scratch.path}/credentials.toml')
      ..writeAsStringSync(_realShape);
    final runner = FakeCliRunner(exited(0));
    final store = GridSessionStore(file: file, runner: runner);
    await store.load();

    // The guard that is the whole design, and it lives in the STORE rather than
    // at each caller: every run mints a fresh 365-day session and revokes
    // nothing.
    final failure = await store.signIn();

    expect(failure, isNull);
    expect(runner.calls, isEmpty);
    expect(store.value?.token, 'session-abc');
  });

  test('signIn re-reads before deciding, so two callers cannot race', () async {
    final file = File('${scratch.path}/credentials.toml');
    final runner = FakeCliRunner(exited(0));
    final store = GridSessionStore(file: file, runner: runner);
    await store.load();
    expect(store.signedIn, isFalse, reason: 'it saw an empty machine');

    // Somebody signed in between that read and this call — the bootstrap
    // winning its race with the pane's button, or a terminal.
    file.writeAsStringSync(_realShape);
    final failure = await store.signIn();

    expect(failure, isNull);
    expect(
      runner.calls,
      isEmpty,
      reason: 'a stale "signed out" must not mint a second session',
    );
  });

  // --- whose session it is -------------------------------------------------
  //
  // `harness logout` never deletes ~/.grid/credentials.toml, so signing out and
  // back in as somebody else used to leave the previous person's session on
  // disk — and the app went on listing THEIR grids with nothing in the UI that
  // could correct it.

  test('a session belonging to somebody else is replaced', () async {
    final file = File('${scratch.path}/credentials.toml')
      ..writeAsStringSync(_realShape);
    final runner = FakeCliRunner(
      exited(0, stdout: '{"type":"result","status":"success"}\n'),
      onRun: (_) => file.writeAsStringSync(
        _realShape
            .replaceAll('someone@example.test', 'newcomer@example.test')
            .replaceAll('session-abc', 'session-xyz'),
      ),
    );
    final store = GridSessionStore(file: file, runner: runner);
    await store.load();

    final failure = await store.signIn(account: 'newcomer@example.test');

    expect(failure, isNull);
    // Plain `grid login` — never `--force`, which is the HARNESS sign-in's flag
    // and stops the daemon this app is talking to.
    expect(runner.calls.single, ['grid', 'login', '--json']);
    expect(store.value?.email, 'newcomer@example.test');
  });

  test('a session for the same account is left exactly alone', () async {
    final file = File('${scratch.path}/credentials.toml')
      ..writeAsStringSync(_realShape);
    final runner = FakeCliRunner(exited(0));
    final store = GridSessionStore(file: file, runner: runner);
    await store.load();

    // Case matters nowhere in an address, and a re-mint here would be the
    // 365-day pile-up the guard exists to prevent.
    final failure = await store.signIn(account: 'SOMEONE@Example.Test');

    expect(failure, isNull);
    expect(runner.calls, isEmpty);
    expect(store.value?.token, 'session-abc');
  });

  test('an unknown account leaves whoever is there alone', () async {
    final file = File('${scratch.path}/credentials.toml')
      ..writeAsStringSync(_realShape);
    final runner = FakeCliRunner(exited(0));
    final store = GridSessionStore(file: file, runner: runner);
    await store.load();

    // "We have not asked yet" must never read as "they differ": the profile
    // call can simply have failed, and re-minting over a slow network call is
    // exactly the wrong reading.
    expect(await store.signIn(), isNull);
    expect(await store.signIn(account: ''), isNull);
    expect(runner.calls, isEmpty);
  });

  // --- signing out ---------------------------------------------------------

  test('signOut clears the session, this machine only', () async {
    final file = File('${scratch.path}/credentials.toml')
      ..writeAsStringSync(_realShape);
    final runner = FakeCliRunner(
      exited(0, stdout: '{"type":"result","status":"success"}\n'),
      onRun: (_) => file.deleteSync(),
    );
    final store = GridSessionStore(file: file, runner: runner);
    await store.load();

    final failure = await store.signOut();

    expect(failure, isNull);
    // `--everywhere` would sign out every other machine on the account.
    expect(runner.calls.single, ['grid', 'logout', '--json']);
    expect(store.signedIn, isFalse);
  });

  test('signOut with nothing to clear runs no CLI', () async {
    final runner = FakeCliRunner(exited(0));
    final store = GridSessionStore(
      file: File('${scratch.path}/absent.toml'),
      runner: runner,
    );
    await store.load();

    expect(await store.signOut(), isNull);
    expect(runner.calls, isEmpty);
  });

  test('a sign-out that left the credential says so', () async {
    // The file is the only thing that decides, whatever the command claimed —
    // and the caller must be able to tell the user their credential is still
    // on the machine.
    final file = File('${scratch.path}/credentials.toml')
      ..writeAsStringSync(_realShape);
    final store = GridSessionStore(
      file: file,
      runner: FakeCliRunner(
        exited(1, stderr: 'a serve child on this box could not be stopped'),
      ),
    );
    await store.load();

    final failure = await store.signOut();

    expect(failure, contains('still signed in to Grid'));
    expect(failure, contains('could not be stopped'));
    expect(store.signedIn, isTrue);
  });

  // --- what the client does with it ---------------------------------------

  test('with no session the client refuses before it opens a socket', () async {
    final store = GridSessionStore(
      file: File('${scratch.path}/absent.toml'),
      runner: FakeCliRunner(exited(0)),
    );
    await store.load();
    final client = GridApiClient(session: store);

    await expectLater(client.me(), throwsA(isA<GridSignedOutException>()));
  });

  test(
    'a late session un-sticks a pane that already said signed out',
    () async {
      final file = File('${scratch.path}/credentials.toml');
      final store = GridSessionStore(
        file: file,
        runner: FakeCliRunner(exited(0)),
      );
      await store.load();
      final controller = GridNetworksController(
        client: GridApiClient(session: store),
        session: store,
      );
      addTearDown(controller.dispose);

      await controller.refresh();
      expect(controller.state, isA<GridNetworksSignedOut>());

      // The bootstrap sign-in lands a moment later. `ensureLoaded` only fetches
      // from Idle, so without the store being watched the pane would sit on its
      // sign-in card for the life of the screen.
      file.writeAsStringSync(_realShape);
      await store.load();
      await Future<void>.delayed(Duration.zero);

      expect(controller.state, isNot(isA<GridNetworksSignedOut>()));
    },
  );

  test(
    'the grids on screen do not outlive the account that fetched them',
    () async {
      // The bug this covers, end to end: sign out of Harness, sign in as
      // somebody else, and every grid list in the app went on showing the
      // previous account's grids — the share picker offering one grid the new
      // account is not even on — until the app was restarted.
      final file = File('${scratch.path}/credentials.toml')
        ..writeAsStringSync(_realShape);
      final store = GridSessionStore(
        file: file,
        runner: FakeCliRunner(exited(0)),
      );
      await store.load();
      final api = FakeGridApi();
      final controller = GridNetworksController(client: api, session: store);
      addTearDown(controller.dispose);

      await controller.refresh();
      expect(api.calls, 1);

      // Somebody else signs in. Same file, different token.
      file.writeAsStringSync(_otherAccount);
      await store.load();
      await Future<void>.delayed(Duration.zero);

      expect(
        api.calls,
        2,
        reason: 'a list fetched with the old token is wrong, not merely old',
      );
    },
  );

  test('signing out of Grid takes the list with it', () async {
    final file = File('${scratch.path}/credentials.toml')
      ..writeAsStringSync(_realShape);
    final store = GridSessionStore(file: file, runner: FakeCliRunner(exited(0)));
    await store.load();
    final controller = GridNetworksController(
      client: FakeGridApi(),
      session: store,
    );
    addTearDown(controller.dispose);

    await controller.refresh();
    expect(controller.state, isA<GridNetworksReady>());

    // `grid logout` deletes the file.
    file.deleteSync();
    await store.load();
    await Future<void>.delayed(Duration.zero);

    // Not the old list: every grid in it is now a launch that fails at the
    // point of use, and the pane has a sign-in card for exactly this.
    expect(controller.state, isA<GridNetworksSignedOut>());
  });

  test('re-reading an unchanged file wakes nobody', () async {
    final file = File('${scratch.path}/credentials.toml')
      ..writeAsStringSync(_realShape);
    final store = GridSessionStore(file: file, runner: FakeCliRunner(exited(0)));
    await store.load();
    var woken = 0;
    store.addListener(() => woken++);

    await store.load();
    await store.load();

    // Every listener on this store either re-asks the Grid API or rebuilds a
    // pane, and the CLI rewrites this file on a token refresh that changes
    // nothing any of them can see.
    expect(woken, 0);
  });

  test('a grid login in a terminal lands without a restart', () async {
    final file = File('${scratch.path}/credentials.toml')
      ..writeAsStringSync(_realShape);
    final store = GridSessionStore(file: file, runner: FakeCliRunner(exited(0)));
    addTearDown(store.dispose);
    await store.load();
    store.watchForChanges();
    expect(store.value?.email, 'someone@example.test');

    // What `grid login` does: write a temp file next to it, then rename it over
    // the top. A watch on the file's own inode would hear nothing about this.
    final temp = File('${scratch.path}/credentials.toml.tmp')
      ..writeAsStringSync(_otherAccount);
    temp.renameSync(file.path);

    // Real filesystem events, so this waits for one rather than pumping: the
    // debounce alone is 250ms, and macOS adds its own latency on top.
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    while (store.value?.email == 'someone@example.test' &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    expect(store.value?.email, 'nobody@example.test');
  });

  test('a signed-out client is a state the pane can offer a fix for', () async {
    final store = GridSessionStore(
      file: File('${scratch.path}/absent.toml'),
      runner: FakeCliRunner(exited(0)),
    );
    await store.load();
    final controller = GridNetworksController(
      client: GridApiClient(session: store),
    );

    await controller.refresh();

    // Not GridNetworksFailed: that one offers Retry, and retrying a sign-out
    // fails identically forever.
    expect(controller.state, isA<GridNetworksSignedOut>());
  });
}
