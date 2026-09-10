import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/codex_profiles.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/engine_availability.dart';
import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/core/models.dart';
import 'package:harness/state/app_state.dart';

class _MemoryStore implements LocalKeyValueStore {
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
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'discovers and links existing account folders without copying credentials',
    () async {
      final home = await Directory.systemTemp.createTemp(
        'harness-codex-profiles-',
      );
      addTearDown(() => home.delete(recursive: true));
      final primary = await Directory('${home.path}/.codex').create();
      final second = await Directory('${home.path}/.codex-account-2').create();
      final custom = await Directory('${home.path}/custom account').create();
      await Directory('${home.path}/.codex-unrelated').create();
      final auth = File('${second.path}/auth.json');
      await File('${primary.path}/config.toml').writeAsString('');
      await auth.writeAsString('secret fixture must remain untouched');
      final storage = _MemoryStore();
      final catalog = LocalCodexProfiles(home: home, storage: storage);
      expect((await catalog.load()).map((p) => p.label), [
        '.codex',
        '.codex-account-2',
      ]);
      final linked = await catalog.link(custom.path);
      final reloaded = LocalCodexProfiles(home: home, storage: storage);
      expect((await reloaded.load()).map((p) => p.path), contains(linked.path));
      expect(await auth.readAsString(), 'secret fixture must remain untouched');
      expect(storage.values.values.join(), isNot(contains('secret fixture')));
      expect(await File('${custom.path}/auth.json').exists(), isFalse);
      await custom.delete();
      expect(
        (await reloaded.load()).map((p) => p.path),
        isNot(contains(linked.path)),
      );
    },
  );

  test(
    'does not interpret shell aliases or relative paths as account folders',
    () async {
      final home = await Directory.systemTemp.createTemp(
        'harness-codex-paths-',
      );
      addTearDown(() => home.delete(recursive: true));
      final catalog = LocalCodexProfiles(home: home, storage: _MemoryStore());
      for (final path in ['codex2', '~/.codex-two', '/tmp/bad\npath']) {
        await expectLater(catalog.resolve(path), throwsFormatException);
      }
    },
  );

  test('requires explicit CLI capability, never infers it from the installed binary', () {
    expect(
      EngineAvailability.fromJson({'engine': 'codex', 'installed': true})
          ?.supportsCodexHome,
      isFalse,
    );
    expect(
      EngineAvailability.fromJson({
        'engine': 'codex',
        'supportsCodexHome': true,
      })?.supportsCodexHome,
      isTrue,
    );
    expect(
      EngineAvailability.fromJson({
        'engine': 'claude',
        'supportsCodexHome': true,
      })?.supportsCodexHome,
      isFalse,
    );
  });

  test('refuses an explicit profile before contacting an old CLI or a remote machine', () async {
    final notifier = AppNotifier(
      config: AppConfig.dev,
      authSession: AuthSession(),
      configStore: null,
    );
    addTearDown(notifier.dispose);
    final machine = MachineState(
      const Machine(machineId: 'local', authMode: MachineAuthMode.remote),
    )..localOnly = true;
    notifier.machineStates['local'] = machine;
    expect(
      await notifier.createAgent(
        'local',
        engine: 'codex',
        folder: '/work',
        codexHome: '/accounts/two',
      ),
      contains('Update the harness CLI'),
    );
    machine.engines.replace(const [
      EngineAvailability(
        engine: 'codex',
        installed: true,
        supportsCodexHome: true,
      ),
    ]);
    machine.localOnly = false;
    expect(
      await notifier.createAgent(
        'local',
        engine: 'codex',
        folder: '/work',
        codexHome: '/accounts/two',
      ),
      contains('this computer'),
    );
    machine.localOnly = true;
    expect(
      await notifier.createAgent(
        'local',
        engine: 'claude',
        folder: '/work',
        codexHome: '/accounts/two',
      ),
      contains('only for Codex'),
    );
  });

  test('keeps a full profile path through agent updates and rename', () {
    final path = '/accounts/${'long-name-' * 15}/codex-two';
    final agent = Agent.fromJson({
      'id': 'one',
      'engine': 'codex',
      'codexHome': path,
    });
    expect(agent.codexHome, path);
    expect(agent.copyWith(name: 'renamed').codexHome, path);
    final changed = Agent.fromJson({
      'id': 'one',
      'engine': 'codex',
      'codexHome': '/accounts/other',
    });
    expect(AppNotifier.agentsEqual([agent], [changed]), isFalse);
    expect(
      Agent.fromJson({'id': 'one', 'engine': 'claude', 'codexHome': path})
          .codexHome,
      isNull,
    );
  });
}
