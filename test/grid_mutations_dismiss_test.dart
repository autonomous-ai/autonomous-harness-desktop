import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/grid/grid_access_type.dart';
import 'package:harness/grid/grid_mutations_controller.dart';
import 'package:harness/grid/grid_network.dart';
import 'package:harness/grid/grid_networks_controller.dart';
import 'package:harness/grid/grid_selection_store.dart';
import 'package:harness/settings/sections/grid_section.dart';
import 'package:harness/share/grid_cli.dart';
import 'package:harness/shared/theme/app_theme.dart';

import 'support/fake_grid_api.dart';

class _MemoryStore implements LocalKeyValueStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// A create that only lands when the test says so.
class _SlowApi extends FakeGridApi {
  final gate = Completer<void>();
  final List<String> created = [];

  @override
  Future<GridNetwork> createNetwork({
    required String name,
    required GridAccessType type,
  }) async {
    await gate.future;
    created.add(name);
    return GridNetwork.fromJson({
      'network_id': 'grid-new',
      'name': name,
      'owner_email': 'huy@example.com',
      'network_type': type.wire,
      'status': 'active',
      'router_enabled': false,
      'router_advisors': const [],
    });
  }
}

class _Cli extends GridCli {
  _Cli() : super(environment: const {'HOME': '/tmp/fake-home'});
  final List<List<String>> ran = [];
  @override
  Future<String?> locate() async => '/usr/local/bin/grid';
  @override
  Future<GridCliResult> run(List<String> a) async {
    ran.add(a);
    return const GridCliResult(exitCode: 0, stdout: '', stderr: '');
  }
}

// Escape and a barrier click pop a dialog even when its Cancel button is
// disabled. Without a PopScope that cost a create its feedback entirely: the
// form closed, the call carried on, the grid was made, `grid use` repointed
// this computer at it — and nothing was ever said, because the dialog had
// resolved to null. The user had cancelled something that happened anyway.
void main() {
  testWidgets('escape does not abandon a create in flight', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = _SlowApi();
    final cli = _Cli();
    final networks = GridNetworksController(client: api);
    final mutations = GridMutationsController(
      client: api,
      cli: cli,
      networks: networks,
      selection: GridSelectionStore(storage: _MemoryStore()),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(brightness: Brightness.light),
        home: Builder(
          builder: (context) {
            AppTheme.brightness.value = Brightness.light;
            return BrightnessScope(
              child: Scaffold(
                body: GridSection(controller: networks, mutations: mutations),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('grid-create-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('create-grid-name-field')),
      'escaped grid',
    );
    await tester.tap(find.byKey(const Key('create-grid-submit')));
    await tester.pump();

    expect(mutations.createState, isA<CreateGridSubmitting>());

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    // Not pumpAndSettle: the spinner is a running animation, so settling
    // never returns while the call is in flight.
    await tester.pump();
    expect(
      find.text('Create grid'),
      findsOneWidget,
      reason: 'the form stays put while the call it started is still running',
    );

    api.gate.complete();
    await tester.pumpAndSettle();

    // The call could not be recalled — but its result is now reported rather
    // than swallowed, which is the whole point.
    expect(api.created, ['escaped grid']);
    expect(cli.ran, [
      ['sync'],
      ['use', 'grid-new'],
    ]);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Grid “escaped grid” created.'), findsOneWidget);
  });
}
