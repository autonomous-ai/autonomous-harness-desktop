// The panel that replaced the header's dropdown. What is asserted here is what
// the dropdown could not do: show the models of EVERY provider this computer
// offers at once, let a search cross them, and be walked without the mouse.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/grid/grid_models_controller.dart';
import 'package:harness/grid/grid_network.dart';
import 'package:harness/grid/grid_networks_controller.dart';
import 'package:harness/grid/model_picker_options.dart';
import 'package:harness/grid/model_recents_store.dart';
import 'package:harness/grid/provider_enablement_store.dart';
import 'package:harness/shared/widgets/app_menu.dart';
import 'package:harness/widgets/model_picker_dialog.dart';

import 'support/fake_grid_api.dart';

/// The two grids `kGridMePayload` describes.
const kOfficeId = 'grid-aaf6a46ced4f42f9';
const kOfficeName = 'hp-1-1';
const kWaterId = 'grid-e3b210eacc5b4cdf';
const kWaterName = 'Water Grid';

class _MemoryStore implements LocalKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// The answer one opening of the panel popped with, and whether it popped at
/// all — a dialog left open and one that closed on null are different failures.
class _Picked {
  ModelChoice? choice;
  bool closed = false;
}

/// An account whose `/v1/grid/me` never answers, so the panel can be caught in
/// the state it opens in.
class _SlowGridApi extends FakeGridApi {
  @override
  Future<GridMe> me() => Completer<GridMe>().future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeGridApi api;
  late GridNetworksController networks;
  late GridModelsController models;
  late ModelRecentsStore recents;
  late ProviderEnablementStore enablement;
  late _Picked picked;

  setUp(() {
    api = FakeGridApi();
    networks = GridNetworksController(client: api);
    models = GridModelsController(client: api);
    recents = ModelRecentsStore(storage: _MemoryStore());
    // Never loaded, so nothing is disabled — the file is named only so the
    // store cannot reach the developer's real `providers_config.json`.
    enablement = ProviderEnablementStore(
      file: File('${Directory.systemTemp.path}/harness-test-providers.json'),
    );
    picked = _Picked();
  });

  tearDown(() {
    networks.dispose();
    models.dispose();
    recents.dispose();
    enablement.dispose();
  });

  /// Opens the picker over a real Navigator and settles it — the account's own
  /// fetch, then each provider's models.
  ///
  /// Through a button rather than `showDialog` on a bare context: the panel
  /// POPS with its answer, and a test that never took the route cannot see what
  /// it popped.
  Future<void> pumpPicker(WidgetTester tester, {ModelChoice? current}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked.choice = await showDialog<ModelChoice>(
                  context: context,
                  builder: (_) => ModelPickerDialog(
                    current: current,
                    networks: networks,
                    models: models,
                    recents: recents,
                    enablement: enablement,
                  ),
                );
                picked.closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('lists every provider the account is on, with its own models', (
    tester,
  ) async {
    await pumpPicker(tester);

    expect(find.text('Select model'), findsOneWidget);
    expect(find.text(kOfficeName), findsOneWidget);
    expect(find.text(kWaterName), findsOneWidget);
    expect(
      find.text('GLM-4.7-Flash'),
      findsNWidgets(2),
      reason: 'one row under each provider — the same id, two relays',
    );
    expect(
      find.text('No provider'),
      findsOneWidget,
      reason: "the engine's own login is a peer of every model",
    );
    expect(
      find.text('Auto'),
      findsNWidgets(2),
      reason:
          "one per provider: the relay advertises its own 'Auto' router in "
          '/models and it must not double the row',
    );
  });

  testWidgets('asks each provider for its models exactly once', (tester) async {
    await pumpPicker(tester);

    expect(api.credentialCalls, 2);
    expect(api.modelBaseUrls, [
      'https://grid.example/$kOfficeId/relay/v1',
      'https://grid.example/$kWaterId/relay/v1',
    ]);
  });

  testWidgets('a provider switched off in Settings is not offered here', (
    tester,
  ) async {
    // The switch means "do not offer me this one", and this is a picker.
    //
    // Set through the notifier rather than through `setEnabled`, which writes
    // its JSON file: a real `File.writeAsString` never completes inside
    // `testWidgets`' fake-async zone, so awaiting one hangs the run rather than
    // failing it (see CLAUDE.md on `SnapshotStore`). What is under test here is
    // the picker's reading of the set, not the store's round trip — that has
    // its own test.
    enablement.value = const {kWaterId};
    await pumpPicker(tester);

    expect(find.text(kOfficeName), findsOneWidget);
    expect(find.text(kWaterName), findsNothing);
  });

  testWidgets(
    'the search crosses providers, and says so when nothing matches',
    (tester) async {
      await pumpPicker(tester);

      await tester.enterText(
        find.byKey(const Key('model-picker-search')),
        'glm',
      );
      await tester.pumpAndSettle();
      expect(find.text('GLM-4.7-Flash'), findsNWidgets(2));
      expect(
        find.text('No provider'),
        findsNothing,
        reason: 'a row that does not match is not an exception to the search',
      );

      await tester.enterText(
        find.byKey(const Key('model-picker-search')),
        'gpt',
      );
      await tester.pumpAndSettle();
      expect(find.text('No matches'), findsOneWidget);
    },
  );

  testWidgets('↓ walks past the headers, and ↵ picks the row under it', (
    tester,
  ) async {
    await pumpPicker(tester);

    // The panel opens on the first row ("No provider"); two steps down is the
    // first provider's first MODEL — the group header between them is skipped,
    // and its Auto row is the step in between.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(picked.closed, isTrue);
    expect(picked.choice?.networkId, kOfficeId);
    expect(picked.choice?.networkName, kOfficeName);
    expect(
      picked.choice?.model,
      'GLM-4.7-Flash',
      reason: 'a model id means nothing without the relay that answers for it',
    );
  });

  testWidgets('opens on the row the agent is running, not on the first one', (
    tester,
  ) async {
    // That row does not exist on the frame the panel opens on — its provider's
    // models are a round trip away — so a highlight placed once, on the first
    // build, left every open sitting on "No provider" and one keystroke from
    // taking the agent off its provider entirely.
    await pumpPicker(
      tester,
      current: const ModelChoice(networkId: kOfficeId, model: 'GLM-4.7-Flash'),
    );

    final rows = tester
        .widgetList<AppMenuItem>(find.byType(AppMenuItem))
        .toList();
    final current = rows.firstWhere((row) => row.selected);
    expect(current.label, 'GLM-4.7-Flash');
    expect(
      current.highlighted,
      isTrue,
      reason: 'the panel opens on the row it ticks',
    );
    expect(
      rows.first.highlighted,
      isFalse,
      reason: '"No provider" is the fallback, not the resting place',
    );

    // And it is the row Enter acts on, with no arrow key first.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(picked.choice?.model, 'GLM-4.7-Flash');
    expect(picked.choice?.networkId, kOfficeId);
  });

  testWidgets('a late provider does not yank the highlight off an arrow key', (
    tester,
  ) async {
    // The other half of the rule above: once the reader has taken the keyboard,
    // the highlight is theirs, whatever lands afterwards.
    await pumpPicker(
      tester,
      current: const ModelChoice(networkId: kOfficeId, model: 'GLM-4.7-Flash'),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    // Models are already in by now; re-notifying is what a slow provider's
    // answer looks like from here.
    models.debugSetState(kWaterId, const GridModelsReady(['GLM-4.7-Flash']));
    await tester.pumpAndSettle();

    final rows = tester
        .widgetList<AppMenuItem>(find.byType(AppMenuItem))
        .toList();
    expect(rows.firstWhere((row) => row.selected).highlighted, isFalse);
    expect(rows.where((row) => row.highlighted), hasLength(1));
  });

  testWidgets('a tap on a row resolves the same way', (tester) async {
    await pumpPicker(tester);

    await tester.tap(find.text('No provider'));
    await tester.pumpAndSettle();

    expect(picked.closed, isTrue);
    expect(picked.choice, ModelChoice.none);
  });

  testWidgets('an account still loading says so instead of showing nothing', (
    tester,
  ) async {
    // Two states that must not render the same: "we have not asked yet" and
    // "your search matched nothing".
    final slow = GridNetworksController(client: _SlowGridApi());
    addTearDown(slow.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModelPickerDialog(
            current: null,
            networks: slow,
            models: models,
            recents: recents,
            enablement: enablement,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Loading providers…'), findsOneWidget);
    expect(find.text('No matches'), findsNothing);
  });

  testWidgets('the last picks sit at the top, named by their provider', (
    tester,
  ) async {
    await recents.remember(
      const ModelChoice(
        networkId: kWaterId,
        networkName: kWaterName,
        model: 'GLM-4.7-Flash',
      ),
    );
    await pumpPicker(tester);

    expect(find.text('Recent'), findsOneWidget);
    expect(
      find.text(kWaterName),
      findsNWidgets(2),
      reason: "the recent row's aside, and the provider's own group header",
    );
    expect(
      find.text('GLM-4.7-Flash'),
      findsNWidgets(3),
      reason: 'the recent row, plus the row under each provider',
    );
  });
}
