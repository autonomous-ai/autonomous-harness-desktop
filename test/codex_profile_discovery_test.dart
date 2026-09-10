import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/codex_profiles.dart';
import 'package:harness/core/local_key_value_store.dart';

class _Store implements LocalKeyValueStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  late Directory home;
  late _Store storage;
  setUp(() async {
    home = await Directory.systemTemp.createTemp('codex-profile-discovery-');
    storage = _Store();
  });
  tearDown(() async => home.delete(recursive: true));

  Future<String> folder(String name, {bool marker = false}) async {
    final directory = await Directory('${home.path}/$name')
        .create(recursive: true);
    if (marker) {
      await File('${directory.path}/auth.json')
          .writeAsString('private fixture, not JSON');
    }
    return directory.resolveSymbolicLinks();
  }

  Future<void> script(
    String name,
    String content, {
    bool executable = false,
  }) async {
    final file = File('${home.path}/$name');
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    if (executable) {
      expect((await Process.run('chmod', ['+x', file.path])).exitCode, 0);
    }
  }

  LocalCodexProfiles catalog([Map<String, String> environment = const {}]) =>
      LocalCodexProfiles(
        home: home,
        storage: storage,
        environment: environment,
      );

  test('combines arbitrary environment and observed homes with name variants and linked folders', () async {
    final envHome = await folder('accounts/company');
    final live = await folder('somewhere/active login');
    final named = await folder('.codex2', marker: true);
    final underscore = await folder('.codex_personal', marker: true);
    final xdg = await folder('.config/codex-team', marker: true);
    final linked = await folder('linked manually');
    await folder('unrelated');
    await folder('.codex-unrelated');
    final profiles = catalog({'CODEX_HOME': envHome});
    await profiles.link(linked);
    expect(
      (await profiles.load(observedPaths: {live})).map((p) => p.path),
      unorderedEquals([envHome, live, named, underscore, xdg, linked]),
    );
    // Discovering does not turn all transient candidates into saved links.
    expect(jsonDecode(storage.values.values.single), [linked]);
  });

  test(
    'reads aliases and functions with spaces, HOME, braced variables and tilde',
    () async {
      final expected = [
        await folder('my accounts/work'),
        await folder('my accounts/personal'),
        await folder('my accounts/function'),
        await folder('braced'),
        await folder('tilde'),
      ];
      await script('.zshrc', r'''
export ACCOUNTS="$HOME/my accounts"
alias daily='CODEX_HOME="$ACCOUNTS/work" codex'
alias private="env CODEX_HOME='${HOME}/my accounts/personal' codex"
function whatever() { local CODEX_HOME="$ACCOUNTS/function"; command codex "$@"; }
alias brace='CODEX_HOME=${HOME}/braced codex'
alias tilde='CODEX_HOME=~/tilde codex'
''');
      expect(
        (await catalog().load()).map((p) => p.path),
        unorderedEquals(expected),
      );
    },
  );

  test('an empty default directory does not create a second profile', () async {
    await folder('.codex');
    final single = await folder('.codex_work', marker: true);
    expect((await catalog().load()).map((p) => p.path), [single]);
  });

  test('follows sourced files and arbitrary executable shortcut names without executing them', () async {
    final alias = await folder('profiles/alias');
    final privateBin = await folder('profiles/private-bin');
    final localBin = await folder('profiles/local-bin');
    await script('.zshrc', r'''
source "$HOME/shell/accounts"
export PATH="$HOME/custom tools:$PATH"
''');
    await script('shell/accounts', r'''
source "$HOME/.zshrc"
alias launch='"$HOME/scripts/anything at all"'
''');
    await script('scripts/anything at all', r'''#!/bin/sh
touch "$HOME/MUST_NOT_EXECUTE"
exec env "CODEX_HOME=$HOME/profiles/alias" codex "$@"
''', executable: true);
    await script('custom tools/do-work', r'''#!/usr/bin/env bash
export CODEX_HOME="$HOME/profiles/private-bin"
exec codex "$@"
''', executable: true);
    await script('.local/bin/no-codex-in-this-name', r'''#!/bin/zsh
exec env CODEX_HOME="$HOME/profiles/local-bin" /opt/bin/codex "$@"
''', executable: true);
    expect(
      (await catalog().load()).map((p) => p.path),
      unorderedEquals([alias, privateBin, localBin]),
    );
    expect(await File('${home.path}/MUST_NOT_EXECUTE').exists(), isFalse);
  });

  test('reads custom ZDOTDIR and fish configuration', () async {
    final zsh = await folder('profiles/zsh');
    final fish = await folder('profiles/fish');
    final func = await folder('profiles/fish-function');
    await script('shell/zsh/.zshrc', r'export CODEX_HOME="$HOME/profiles/zsh"');
    await script(
      '.config/fish/conf.d/work.fish',
      r'set -gx CODEX_HOME "$HOME/profiles/fish"',
    );
    await script('.config/fish/functions/anything.fish', r'''
function anything
  set --local --export CODEX_HOME "$HOME/profiles/fish-function"
  codex $argv
end
''');
    await script('.zshenv', r'export ZDOTDIR="$HOME/shell/zsh"');
    expect(
      (await catalog().load()).map((p) => p.path),
      unorderedEquals([zsh, fish, func]),
    );
  });

  test(
    'ignores comments, data, computed paths and unknown variables',
    () async {
      final valid = await folder('valid');
      await folder('wrong');
      await folder('old/wrong');
      await script('.zshrc', r'''
# export CODEX_HOME="$HOME/wrong"
echo "CODEX_HOME=$HOME/wrong"
eval 'CODEX_HOME="$HOME/wrong"'
CODEX_HOME=$(touch "$HOME/MUST_NOT_EXECUTE"; export CODEX_HOME="$HOME/wrong")
CODEX_HOME="$UNKNOWN/wrong"
CODEX_HOME='$HOME/wrong'
BASE="$HOME/old"
BASE=$(compute-path)
alias unresolved='CODEX_HOME="$BASE/wrong" codex'
export CODEX_HOME="$HOME/valid"
''');
      expect((await catalog().load()).map((p) => p.path), [valid]);
      expect(await File('${home.path}/MUST_NOT_EXECUTE').exists(), isFalse);
    },
  );

  test(
    'deduplicates symlinks across all sources and omits vanished profiles',
    () async {
      final actual = await folder('accounts/shared');
      final alias = '${home.path}/symlink';
      await Link(alias).create(actual);
      await script('.bashrc', r'export CODEX_HOME="$HOME/symlink"');
      await catalog().link(alias);
      final profiles = catalog({'CODEX_HOME': actual});
      expect(
        (await profiles.load(observedPaths: {alias, actual}))
            .map((p) => p.path),
        [actual],
      );
      await Directory(actual).delete();
      expect(await profiles.load(observedPaths: {actual}), isEmpty);
    },
  );

  test('leaves credentials, binaries and oversized scripts unread as shell declarations', () async {
    final defaultHome = await folder('.codex');
    await folder('wrong');
    final credentialText = 'export CODEX_HOME="${home.path}/wrong"';
    await script('.codex/auth.json', credentialText);
    await Link('${home.path}/hidden-credentials')
        .create('${home.path}/.codex/auth.json');
    await script('.zshrc', r'''
source "$HOME/.codex/auth.json"
source "$HOME/hidden-credentials"
''');
    await script(
      '.local/bin/oversized',
      '#!/bin/sh\n${'#' * (64 * 1024)}\n$credentialText\n',
      executable: true,
    );
    await script(
      '.local/bin/binary',
      '#!/bin/sh\n\x00$credentialText\n',
      executable: true,
    );
    expect((await catalog().load()).map((p) => p.path), [defaultHome]);
    expect(
      await File('${home.path}/.codex/auth.json').readAsString(),
      credentialText,
    );
  });
}
