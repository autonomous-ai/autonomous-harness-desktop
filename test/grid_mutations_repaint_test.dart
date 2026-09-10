import 'dart:async';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/grid/grid_mutations_controller.dart';
import 'package:harness/grid/grid_networks_controller.dart';
import 'package:harness/grid/grid_selection_store.dart';
import 'package:harness/grid/provider_enablement_store.dart';
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

/// A delete that never finishes, so the spinner has to be visible.
class _HangingApi extends FakeGridApi {
  final completer = Completer<void>();
  @override
  Future<void> deleteNetwork(String networkId) => completer.future;
}

class _Cli extends GridCli {
  _Cli() : super(environment: const {'HOME': '/tmp/fake-home'});
  @override
  Future<String?> locate() async => '/usr/local/bin/grid';
  @override
  Future<GridCliResult> run(List<String> a) async =>
      const GridCliResult(exitCode: 0, stdout: '', stderr: '');
}

// The pane reads `isDeleting` off the mutations controller but hangs its
// builder off the networks one, so a delete that changes only the mutations
// controller's state repaints nothing. It cost the row its in-flight label —
// the click looked like it had done nothing at all.
void main() {
  testWidgets('the row spins while its delete is in flight', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = _HangingApi();
    final networks = GridNetworksController(client: api);
    final mutations = GridMutationsController(
      client: api,
      cli: _Cli(),
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
                body: GridSection(
                  controller: networks,
                  mutations: mutations,
                  // Its own file: the singleton writes the developer's real
                  // ~/.harness, and a test run must not.
                  enablement: ProviderEnablementStore(
                    file: File(
                      '${Directory.systemTemp.createTempSync('providers').path}'
                      '/providers_config.json',
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Selecting the row puts its actions in the detail panel beside the rail.
    await tester.tap(
      find.byKey(const Key('provider-row-grid-aaf6a46ced4f42f9')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('provider-delete-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // The controller says a delete is running...
    expect(mutations.isDeleting('grid-aaf6a46ced4f42f9'), isTrue,
        reason: 'the controller is mid-delete');
    // ...so the row must say so too.
    expect(find.text('Deleting…'), findsOneWidget,
        reason: 'the button should show its in-flight label');

    api.completer.complete();
    await tester.pumpAndSettle();
  });
}
