// The Grid pane is the one screen that talks to a backend the `harness` CLI
// knows nothing about, so what it parses is not covered by anything else. The
// payload it reads lives in `support/fake_grid_api.dart`.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/grid/grid_access.dart';
import 'package:harness/grid/grid_models_controller.dart';
import 'package:harness/grid/grid_network.dart';
import 'package:harness/grid/grid_networks_controller.dart';
import 'package:harness/grid/grid_selection_store.dart';
import 'package:harness/grid/provider_enablement_store.dart';
import 'package:harness/settings/sections/grid_section.dart';
import 'package:harness/settings/sections/grid_hero.dart';
import 'package:harness/settings/settings_section.dart';
import 'package:harness/share/engine_run.dart';
import 'package:harness/share/share_target_store.dart';
import 'package:harness/shared/theme/app_theme.dart';

import 'support/fake_grid_api.dart';

/// A grid whose name IS its access rule, and one whose name is just a name.
final _domainGrid = GridNetwork.fromJson(const {
  'network_id': 'grid-domain',
  'name': 'clc.fitus.edu.vn',
  'owner_email': 'huy@example.com',
  'network_type': 'private-domain',
});
final _invitedGrid = GridNetwork.fromJson(const {
  'network_id': 'grid-invited',
  'name': 'hp-1-1',
  'owner_email': 'huy@example.com',
  'network_type': 'permissioned',
});

/// A relay that serves a different list per grid.
///
/// Needed because the pane re-asks on mount — a state poked in with
/// `debugSetState` is replaced by whatever the client answers, which is the
/// behaviour that makes a model added on another screen show up here.
class _ModelsApi extends FakeGridApi {
  _ModelsApi(this.byNetwork);

  /// network id → what its relay advertises.
  final Map<String, List<String>> byNetwork;

  @override
  Future<List<String>> models({
    required String baseUrl,
    required String apiKey,
  }) async {
    // `FakeGridApi.credentials` builds the URL from the id, which is the only
    // thing tying an answer back to the grid it was asked about.
    for (final entry in byNetwork.entries) {
      if (baseUrl.contains(entry.key)) return entry.value;
    }
    return const [];
  }
}

/// A relay that never answers, so a provider stays in Loading.
class _HangingApi extends FakeGridApi {
  @override
  Future<List<String>> models({
    required String baseUrl,
    required String apiKey,
  }) => Completer<List<String>>().future;
}

/// The pane writes the pick straight through to disk; tests keep it in memory.
class _MemoryStore implements LocalKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GridMe.fromJson', () {
    final me = GridMe.fromJson(Map<String, dynamic>.from(kGridMePayload));

    test('reads the account and every grid on it', () {
      expect(me.user.email, 'huy@example.com');
      expect(me.user.name, 'Huy Pham');
      expect(me.networks.length, 2);
    });

    test('an owned grid carries its roles, router and creation date', () {
      final owned = me.networks.first;
      expect(owned.displayName, 'hp-1-1');
      expect(owned.isOwnedBy('huy@example.com'), isTrue);
      // The API answers in seconds; a date read as milliseconds would land in
      // 1970 and the card would print it.
      expect(owned.createdAt?.year, 2026);
      expect(owned.routerEnabled, isTrue);
      expect(owned.routerAdvisors, ['openai/gpt-5-mini']);
      expect(owned.member?.roles, ['admin', 'both']);
      expect(owned.member?.isAdmin, isTrue);
    });

    test('a grid owned by someone else is not reported as yours', () {
      final other = me.networks.last;
      expect(other.isOwnedBy('huy@example.com'), isFalse);
      expect(other.member?.isAdmin, isFalse);
      expect(other.routerAdvisors, isEmpty);
      // Absent fields must not throw or invent a value.
      expect(other.createdAt, isNull);
      expect(other.description, isNull);
    });

    test('a grid with no name falls back to its id', () {
      final unnamed = GridNetwork.fromJson({
        'network_id': 'grid-1',
        'name': '   ',
        'owner_email': 'a@b.c',
      });
      expect(unnamed.displayName, 'grid-1');
      expect(unnamed.member, isNull);
      expect(unnamed.routerEnabled, isFalse);
    });
  });

  group('GridNetworksController', () {
    test('ensureLoaded fetches once, refresh fetches again', () async {
      final api = FakeGridApi();
      final controller = GridNetworksController(client: api);
      addTearDown(controller.dispose);

      expect(controller.state, isA<GridNetworksIdle>());
      controller.ensureLoaded();
      controller.ensureLoaded();
      await Future<void>.delayed(Duration.zero);

      expect(api.calls, 1, reason: 'a second ensureLoaded must not refetch');
      final state = controller.state;
      expect(state, isA<GridNetworksReady>());
      expect((state as GridNetworksReady).me.networks.length, 2);

      await controller.refresh();
      expect(api.calls, 2);
    });

    test(
      'a failed load keeps the message, and retry can still succeed',
      () async {
        final controller = GridNetworksController(
          client: FakeGridApi(error: 'token expired'),
        );
        addTearDown(controller.dispose);

        await controller.refresh();
        final state = controller.state;
        expect(state, isA<GridNetworksFailed>());
        expect(
          (state as GridNetworksFailed).message,
          contains('token expired'),
        );
      },
    );
  });

  group('GridSection', () {
    late GridSelectionStore selection;
    late ProviderEnablementStore enablement;

    setUp(() {
      selection = GridSelectionStore(storage: _MemoryStore());
      // Its own file under a temp dir: the singleton writes the developer's
      // real ~/.harness, and a test run must not.
      enablement = ProviderEnablementStore(
        file: File(
          '${Directory.systemTemp.createTempSync('providers').path}'
          '/providers_config.json',
        ),
      );
    });

    /// A controller over the fake payload, disposed with the test.
    GridNetworksController newController() {
      final controller = GridNetworksController(client: FakeGridApi());
      addTearDown(controller.dispose);
      return controller;
    }

    Future<void> pump(
      WidgetTester tester,
      GridNetworksController c, {
      String? harnessEmail,
      GridModelsController? models,
      ShareTargetStore? shareTarget,
      ValueChanged<SettingsSection>? onShowSection,
      ({String gridId, EngineRunRecord run})? liveEngine,
      // A skeleton breathes forever ([Pulse]), so a pane with one on it never
      // settles. A test that puts a provider in Loading pumps instead.
      bool settle = true,
    }) async {
      // A window the size the app actually opens at. At the 800x600 default the
      // table's viewport is one row tall, so a lazy list never builds the
      // second grid and the test is asserting about a pane no user ever sees.
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // ⚠️ Built HERE and not in the tree below. A controller made inside
      // `builder` is a new one on every rebuild, and the pane asks each
      // provider for its models exactly once — so every answer would land in
      // an instance already thrown away and the list would load forever.
      //
      // Its own instance either way, never the singleton: that one holds a real
      // client, and a pane that asked it for models would reach for the
      // developer's own Grid session.
      final modelsController =
          models ?? GridModelsController(client: FakeGridApi());
      // Only the one made here — an injected controller belongs to the test
      // that passed it, which disposes it itself.
      if (models == null) addTearDown(modelsController.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(brightness: Brightness.light),
          home: Builder(
            builder: (context) {
              AppTheme.brightness.value = Brightness.light;
              return BrightnessScope(
                child: Scaffold(
                  body: GridSection(
                    controller: c,
                    selection: selection,
                    harnessEmail: harnessEmail,
                    enablement: enablement,
                    models: modelsController,
                    shareTarget: shareTarget,
                    // A function, so the pane can re-read it — and so a test
                    // that says nothing about sharing never touches the real
                    // `~/.grid/run`.
                    liveEngine: () => liveEngine,
                    onShowSection: onShowSection,
                  ),
                ),
              );
            },
          ),
        ),
      );
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump();
        await tester.pump();
      }
    }

    Future<GridNetworksController> ready(WidgetTester tester) async {
      final controller = GridNetworksController(client: FakeGridApi());
      addTearDown(controller.dispose);
      await pump(tester, controller);
      return controller;
    }

    testWidgets('says whose providers these are when it is not you', (
      tester,
    ) async {
      final controller = GridNetworksController(client: FakeGridApi());
      addTearDown(controller.dispose);
      await pump(tester, controller, harnessEmail: 'someone-else@example.com');

      // The bootstrap sign-in leaves an existing session alone whoever owns it,
      // so saying so here is the only thing standing between a person and
      // another account's grids read as their own.
      expect(find.byKey(const Key('grid-account-mismatch')), findsOneWidget);
      expect(find.textContaining('huy@example.com'), findsWidgets);
    });

    testWidgets('says nothing when the two accounts agree', (tester) async {
      final controller = GridNetworksController(client: FakeGridApi());
      addTearDown(controller.dispose);
      await pump(tester, controller, harnessEmail: 'HUY@example.com');

      // Case-insensitively: an address is not two accounts for being typed
      // with a capital.
      expect(find.byKey(const Key('grid-account-mismatch')), findsNothing);
    });

    testWidgets('says nothing before the Harness profile lands', (
      tester,
    ) async {
      await ready(tester);

      // A warning that flashes on every open while the profile loads is a
      // warning people stop reading.
      expect(find.byKey(const Key('grid-account-mismatch')), findsNothing);
    });

    testWidgets('lists every provider, marking the one you own', (
      tester,
    ) async {
      await ready(tester);

      expect(find.text('Providers'), findsOneWidget);
      expect(find.textContaining('huy@example.com'), findsWidgets);
      // Once in the rail; the detail panel prints the selected one again, which
      // is why these are `findsWidgets` rather than `findsOneWidget`.
      expect(find.text('hp-1-1'), findsWidgets);
      expect(find.text('Water Grid'), findsOneWidget);
      // Ownership is stated, not left to the reader to work out from an email.
      expect(find.text('YOURS'), findsOneWidget);
      // The access rule in plain language, and ONLY in the panel: it is Grid's
      // vocabulary for membership, which under a heading that says Providers
      // reads as a property of the service rather than of the roster.
      expect(find.text('Invite only'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('provider-row-grid-aaf6a46ced4f42f9')),
          matching: find.textContaining('Invite only'),
        ),
        findsNothing,
        reason: 'the rail line says what the provider gives, not who may join',
      );
      // The control plane's own spelling never reaches the screen.
      expect(find.text('permissioned-public'), findsNothing);
      expect(find.text('permissioned-providers'), findsNothing);
      expect(find.text('admin'), findsNothing);
      // The rail's one line is the models the provider SERVES — read off the
      // relay, not the `router_advisors` it used to count.
      // One, not two: the fake relay answers `Auto` + one real model, and the
      // virtual router is not a model this provider serves.
      expect(find.text('1 model'), findsWidgets);
      expect(find.textContaining('router'), findsNothing);
      expect(find.byKey(const Key('grid-refresh-button')), findsOneWidget);
    });

    // The switch is the pane's new gesture, and what it controls is not what
    // new agents use — it is whether this computer offers the provider at all.
    testWidgets('a switch turns a provider off without changing the default', (
      tester,
    ) async {
      await ready(tester);
      await tester.tap(
        find.byKey(const Key('provider-row-grid-aaf6a46ced4f42f9')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Make default'));
      await tester.pumpAndSettle();
      expect(selection.value.networkId, 'grid-aaf6a46ced4f42f9');

      // Switch the OTHER provider off: the default must not move.
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('provider-row-grid-e3b210eacc5b4cdf')),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();

      expect(enablement.isEnabled('grid-e3b210eacc5b4cdf'), isFalse);
      expect(enablement.isEnabled('grid-aaf6a46ced4f42f9'), isTrue);
      expect(selection.value.networkId, 'grid-aaf6a46ced4f42f9');
    });

    // Switching the default off does not refuse the click — it hands the
    // default on, because a switch that sometimes does nothing is worse than
    // one that says what it did.
    testWidgets('turning the default off hands the default to the next one', (
      tester,
    ) async {
      await ready(tester);
      await tester.tap(
        find.byKey(const Key('provider-row-grid-aaf6a46ced4f42f9')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Make default'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('provider-row-grid-aaf6a46ced4f42f9')),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();

      expect(selection.value.networkId, 'grid-e3b210eacc5b4cdf');
    });

    // The consequence of every switch being off lands on agents launched
    // later, so nothing on this screen would otherwise look wrong.
    testWidgets('every provider off says so, and there is no "No provider" row',
        (tester) async {
      await ready(tester);
      expect(find.text('Running on subscriptions'), findsNothing);

      for (final id in ['grid-aaf6a46ced4f42f9', 'grid-e3b210eacc5b4cdf']) {
        await tester.tap(
          find.descendant(
            of: find.byKey(Key('provider-row-$id')),
            matching: find.byType(Switch),
          ),
        );
        await tester.pumpAndSettle();
      }

      expect(find.text('Running on subscriptions'), findsOneWidget);
      expect(selection.value.hasGrid, isFalse);
      // The row that used to name this state is gone: a state is not a
      // provider, and the list is a list of providers.
      expect(find.text(kNoGridTargetLabel), findsNothing);
    });

    // Selecting a row READS a provider; "Make default" is what changes where
    // agents launch. They were one gesture before, which made it impossible to
    // look at a provider without also moving every new agent onto it.
    testWidgets('selecting a row reads it; a button makes it the default', (
      tester,
    ) async {
      await ready(tester);
      expect(selection.value.hasGrid, isFalse);

      await tester.tap(
        find.byKey(const Key('provider-row-grid-aaf6a46ced4f42f9')),
      );
      await tester.pumpAndSettle();
      expect(
        selection.value.hasGrid,
        isFalse,
        reason: 'reading a provider is not launching agents on it',
      );

      await tester.tap(find.text('Make default'));
      await tester.pumpAndSettle();
      expect(selection.value.networkId, 'grid-aaf6a46ced4f42f9');
      expect(selection.value.networkName, 'hp-1-1');
      // The button then names the state rather than offering it again.
      expect(find.text('Current default'), findsOneWidget);
    });

    testWidgets('the detail panel describes whatever the rail has selected', (
      tester,
    ) async {
      await ready(tester);
      // No model control at all — a model is chosen per agent, in the agent
      // view's header, not for the provider as a whole.
      expect(find.byKey(const Key('grid-model-trigger')), findsNothing);

      await tester.tap(
        find.byKey(const Key('provider-row-grid-e3b210eacc5b4cdf')),
      );
      await tester.pumpAndSettle();

      // The panel prints the facts the rail has no room for, by name.
      expect(find.text('Provider ID'), findsOneWidget);
      expect(find.text('grid-e3b210eacc5b4cdf'), findsOneWidget);
      expect(find.text('someone@else.com'), findsOneWidget);
      // The headline card the pane used to carry is gone: its facts were the
      // selected row's, printed a second time 200px away.
      expect(find.text('NEW AGENTS USE'), findsNothing);
      expect(find.byType(GridHero), findsNothing);
      expect(find.byKey(const Key('grid-model-trigger')), findsNothing);
    });

    // The drawer this replaced held six facts a chevron away. The point of the
    // split is that they are simply on screen — including the advisor names,
    // which the old table could only afford to count.
    testWidgets('every fact is on screen, with nothing behind a drawer', (
      tester,
    ) async {
      await ready(tester);
      await tester.tap(
        find.byKey(const Key('provider-row-grid-aaf6a46ced4f42f9')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Provider ID'), findsOneWidget);
      expect(find.text('Signaling'), findsOneWidget);
      expect(find.text('Who can join'), findsOneWidget);
      expect(find.text('Owner'), findsOneWidget);
      // The router is gone from the panel: it answered a question about how a
      // request is dispatched INSIDE the grid, in the control plane's own
      // vocabulary, on a screen about which models a person can use. What the
      // provider serves is under MODELS instead.
      expect(find.text('Router'), findsNothing);
      expect(find.text('openai/gpt-5-mini'), findsNothing);
      expect(find.text('MODELS'), findsOneWidget);
      // Deliberately NOT among them: it is the control plane's wire spelling of
      // the rule "Who can join" states two rows above, and printing both asks
      // the reader to reconcile two spellings of one thing.
      expect(find.text('Provider type'), findsNothing);
      expect(find.text('permissioned-public'), findsNothing);
      // Reading a provider is not asking to launch agents on it.
      expect(selection.value.hasGrid, isFalse);
    });

    // What the provider SERVES — the question the panel's facts raise and none
    // of them answers. The names are the point: a count is what the rail
    // affords, and "3 models" is not an answer to "which three".
    testWidgets('the panel names the models, the rail counts them', (
      tester,
    ) async {
      final models = GridModelsController(
        client: _ModelsApi({
          'grid-aaf6a46ced4f42f9': ['qwen3-coder-30b', 'gpt-oss-120b'],
          'grid-e3b210eacc5b4cdf': [],
        }),
      );
      addTearDown(models.dispose);
      await pump(tester, newController(), models: models);

      expect(find.text('qwen3-coder-30b'), findsOneWidget);
      expect(find.text('gpt-oss-120b'), findsOneWidget);
      expect(find.text('2 models'), findsWidgets);
      // Singular and plural are both spelled, and an empty list is not a
      // failure — it is a provider nobody has put a model on yet.
      expect(find.text('No models'), findsOneWidget);
    });

    // The models arrive over two round trips against a relay that may be
    // asleep, so the pane has to be honest about all four states rather than
    // rendering "nothing yet" and "nothing at all" the same.
    testWidgets('a provider still being asked does not read as an empty one', (
      tester,
    ) async {
      final models = GridModelsController(client: _HangingApi());
      addTearDown(models.dispose);
      await pump(tester, newController(), models: models, settle: false);

      expect(find.byKey(const Key('provider-models-skeleton')), findsOneWidget);
      expect(find.text('No models'), findsNothing);
      expect(find.text('Loading models…'), findsWidgets);

      // And a failure keeps its sentence, plus the one thing that can fix it.
      models.debugSetState(
        'grid-aaf6a46ced4f42f9',
        const GridModelsFailed('This provider is asleep.'),
      );
      await tester.pump();
      expect(find.text('This provider is asleep.'), findsOneWidget);
      expect(find.byKey(const Key('provider-models-retry')), findsOneWidget);
    });

    // ⚠️ The relay advertises its virtual `auto` router whether or not anybody
    // is serving, so a grid nobody has joined a node to answers /models with
    // one entry. Counted, that reads as "1 model" on a provider that can
    // answer nothing — and hides the one state the pane most needs to shout
    // about.
    testWidgets('a provider serving only Auto is bare, and says what to do', (
      tester,
    ) async {
      final models = GridModelsController(
        client: _ModelsApi({
          'grid-aaf6a46ced4f42f9': ['Auto'],
          'grid-e3b210eacc5b4cdf': ['Auto', 'qwen3-coder-30b'],
        }),
      );
      addTearDown(models.dispose);
      await pump(
        tester,
        newController(),
        models: models,
        onShowSection: (_) {},
      );

      expect(find.text('Add a model to use this provider.'), findsOneWidget);
      // Twice for the bare provider — its rail line and the panel's heading —
      // while the other one's line counts the single real model it has.
      expect(find.text('No models'), findsNWidgets(2));
      expect(find.text('1 model'), findsOneWidget);
      expect(find.text('Auto'), findsNothing);
      // Loud here, because it is the only thing worth pressing on the panel.
      expect(
        find.descendant(
          of: find.byKey(const Key('provider-add-model')),
          matching: find.byType(FilledButton),
        ),
        findsOneWidget,
      );

      // The provider that HAS a model counts only the real one, and its
      // button goes back to being one option among several.
      await tester.tap(
        find.byKey(const Key('provider-row-grid-e3b210eacc5b4cdf')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Add a model to use this provider.'), findsNothing);
      expect(find.text('qwen3-coder-30b'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('provider-add-model')),
          matching: find.byType(OutlinedButton),
        ),
        findsOneWidget,
      );
    });

    // Putting a model on a provider happens on the OTHER pane, so the button
    // is a door: it pins that pane's grid to this provider and goes there.
    // Without the pin the reader would land on whatever grid the share page
    // was last pointed at and have to find this one again in its picker.
    testWidgets('Add model pins the share target and opens Share Intelligence',
        (tester) async {
      final models = GridModelsController(client: FakeGridApi());
      addTearDown(models.dispose);
      final target = ShareTargetStore(storage: _MemoryStore());
      final opened = <SettingsSection>[];
      await pump(
        tester,
        newController(),
        models: models,
        shareTarget: target,
        onShowSection: opened.add,
      );

      await tester.tap(find.byKey(const Key('provider-add-model')));
      await tester.pumpAndSettle();

      expect(target.value.networkId, 'grid-aaf6a46ced4f42f9');
      expect(
        target.value.networkName,
        'hp-1-1',
        reason: 'the share page names the grid before /v1/grid/me answers',
      );
      expect(opened, [SettingsSection.shareIntelligence]);
    });

    // ⚠️ An engine is detached and joined to ONE grid. `Add model` pins the
    // share target, so pressing it under a live engine would leave that engine
    // serving a grid Share Intelligence no longer names — still answering,
    // still costing whatever it costs, and with no Stop button anywhere for it.
    // That page locks its own picker for exactly this reason; this is the same
    // picker reached from here.
    testWidgets('Add model is refused while this computer is sharing', (
      tester,
    ) async {
      final models = GridModelsController(client: FakeGridApi());
      addTearDown(models.dispose);
      final target = ShareTargetStore(storage: _MemoryStore());
      final opened = <SettingsSection>[];
      await pump(
        tester,
        newController(),
        models: models,
        shareTarget: target,
        onShowSection: opened.add,
        liveEngine: (
          gridId: 'grid-e3b210eacc5b4cdf',
          run: const EngineRunRecord(
            engineId: 'e1',
            gridId: 'grid-e3b210eacc5b4cdf',
            models: ['qwen3-coder-30b'],
            pid: 42,
          ),
        ),
      );

      await tester.tap(
        find.byKey(const Key('provider-add-model')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      // Neither half happened: no pin, and nowhere new.
      expect(target.value.isPinned, isFalse);
      expect(opened, isEmpty);
      // Still on screen, and grey — a button that vanished would teach nobody
      // why. It names the grid being served, since that is where the reader
      // has to go to stop it.
      final button = tester.widget<OutlinedButton>(
        find.descendant(
          of: find.byKey(const Key('provider-add-model')),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(button.onPressed, isNull);
      expect(
        tester
            .widget<Tooltip>(
              find
                  .ancestor(
                    of: find.byKey(const Key('provider-add-model')),
                    matching: find.byType(Tooltip),
                  )
                  .first,
            )
            .message,
        allOf(contains('Water Grid'), contains('Share Intelligence')),
      );
    });

    // A button that pinned a real setting and then went nowhere would be a
    // worse lie than no button.
    testWidgets('with nowhere to send the reader there is no Add model', (
      tester,
    ) async {
      await ready(tester);

      expect(find.byKey(const Key('provider-add-model')), findsNothing);
    });

    // The panel describes a provider; the rail decides whether this computer
    // uses one. A second switch beside a name in 20px type read as the more
    // important of the two copies of one question.
    testWidgets('the panel carries no switch of its own', (tester) async {
      await ready(tester);

      expect(find.byType(Switch), findsNWidgets(2));
      expect(find.text('ENABLED'), findsNothing);
      // Switched off is still a FACT about the provider, so it is still said —
      // as a badge, which nobody can click.
      expect(find.text('DISABLED'), findsNothing);
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('provider-row-grid-aaf6a46ced4f42f9')),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('DISABLED'), findsOneWidget);
    });

    // Rename left the action row for the gesture the name itself suggests.
    testWidgets('the name renames on a double-click, and only if you own it', (
      tester,
    ) async {
      await ready(tester);
      expect(find.text('Rename'), findsNothing);

      await tester.tap(
        find.byKey(const Key('provider-row-grid-e3b210eacc5b4cdf')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('provider-name-grid-e3b210eacc5b4cdf')),
        findsNothing,
        reason: 'a provider somebody else owns answers 403 to a rename',
      );

      await tester.tap(
        find.byKey(const Key('provider-row-grid-aaf6a46ced4f42f9')),
      );
      await tester.pumpAndSettle();
      final name = find.byKey(const Key('provider-name-grid-aaf6a46ced4f42f9'));
      expect(name, findsOneWidget);

      // One click reads it, two open the form.
      //
      // ⚠️ The wait is `pump`, not `pumpAndSettle`. Settling stops as soon as
      // no frame is scheduled — a few milliseconds here — so a single tap
      // followed by the first tap of the double-tap below lands INSIDE
      // kDoubleTapTimeout and the two are read as one double-click, which is
      // how this test first "passed" a dialog it then dismissed with its own
      // third tap.
      await tester.tap(name);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Rename provider'), findsNothing);

      await tester.tap(name);
      // kDoubleTapMinTime (40ms) < this < kDoubleTapTimeout (300ms).
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(name);
      await tester.pumpAndSettle();
      expect(find.text('Rename provider'), findsOneWidget);
    });

    // ⚠️ A `private-domain` grid's NAME is the email domain that may join it.
    // The control plane refuses to create one under any other name and then
    // lets any admin PATCH a new one straight in — so a rename here would
    // change who can use the provider, silently.
    testWidgets('a provider named after its domain cannot be renamed', (
      tester,
    ) async {
      final models = GridModelsController(client: FakeGridApi());
      addTearDown(models.dispose);
      await pump(
        tester,
        newController(),
        models: models,
        harnessEmail: 'huy@example.com',
      );

      // The fixture's owned grid is `permissioned` — renameable.
      expect(
        find.byKey(const Key('provider-name-grid-aaf6a46ced4f42f9')),
        findsOneWidget,
      );

      expect(gridCanBeRenamed(_domainGrid), isFalse);
      expect(gridRenameRefusal(_domainGrid), contains('who can use'));
      expect(gridCanBeRenamed(_invitedGrid), isTrue);
      expect(gridRenameRefusal(_invitedGrid), isNull);
    });

    // Share sits with the name because it is about PEOPLE — who else may use
    // this provider — and not about what this Mac does with it.
    testWidgets('Share sits in the header, not in the action row', (
      tester,
    ) async {
      await ready(tester);

      final share = find.byKey(
        const Key('provider-share-grid-aaf6a46ced4f42f9'),
      );
      expect(share, findsOneWidget);
      // Both header buttons sit above the facts they act on…
      final ownerY = tester.getCenter(find.text('Owner')).dy;
      expect(tester.getCenter(share).dy, lessThan(ownerY));
      expect(tester.getCenter(find.text('Make default')).dy, lessThan(ownerY));
      // …and the one thing nobody can undo is alone at the bottom, past the
      // model list, where it cannot be met on the way to anything else.
      expect(tester.getCenter(find.text('Delete')).dy, greaterThan(ownerY));
    });

    testWidgets('a filter narrows the rail and says so', (tester) async {
      await ready(tester);
      // The heading carries both figures: how many there are, and how many
      // this computer will use.
      expect(find.text('2 providers · 2 enabled'), findsOneWidget);
      expect(find.text('huy@example.com'), findsOneWidget);

      await tester.tap(find.text('You own'));
      await tester.pumpAndSettle();

      expect(find.text('hp-1-1'), findsWidgets);
      expect(find.text('Water Grid'), findsNothing);
      expect(find.textContaining('1 of 2 providers'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('grid-filter-field')),
        'nothing matches this',
      );
      await tester.pumpAndSettle();
      expect(find.text('No provider matches that filter.'), findsOneWidget);
    });

    // The heading is where "how many will this computer use" is answered, now
    // that there is no facet for it: an `Enabled` chip put the word on screen
    // twice, 400px from the switch that actually changes it, and one of the two
    // was a filter — which is the confusion it was removed for.
    testWidgets('the heading count follows the switches', (tester) async {
      await ready(tester);
      expect(find.text('2 providers · 2 enabled'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('provider-row-grid-e3b210eacc5b4cdf')),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 providers · 1 enabled'), findsOneWidget);
      // And no chip claims that word: the switch on each row is the only
      // control that owns it.
      expect(find.widgetWithText(FilterChip, 'Enabled'), findsNothing);
      expect(find.text('Enabled'), findsNothing);
    });

    // Every width the settings pane can actually be. An overflow is a test
    // failure in debug, so this passing IS the assertion — and it is worth
    // having because the panel prints two long mono strings (the id and the
    // signaling URL) that sit visibly close to the right edge.
    for (final width in [1180.0, 1000.0, 900.0, 820.0, 780.0, 700.0, 620.0]) {
      testWidgets('nothing overflows at ${width.toInt()}px', (tester) async {
        await ready(tester);
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a narrow pane stacks the split instead of squeezing it', (
      tester,
    ) async {
      await ready(tester);
      // pump() sizes the window for the common case; this test is about what
      // happens under it, so it narrows the window and rebuilds against it.
      tester.view.physicalSize = const Size(700, 900);
      await tester.pumpAndSettle();

      // Both halves survive — the rail above, the detail below — and nothing
      // was cut off to make room: a squeezed layout overflows, and an overflow
      // is a test failure in debug.
      expect(find.text('hp-1-1'), findsWidgets);
      expect(find.text('Water Grid'), findsOneWidget);
      expect(find.text('Provider ID'), findsOneWidget);
    });

    testWidgets('a failure says so and offers a retry', (tester) async {
      final controller = GridNetworksController(
        client: FakeGridApi(error: 'token expired'),
      );
      addTearDown(controller.dispose);
      await pump(tester, controller);

      expect(find.text('Could not load your providers'), findsOneWidget);
      expect(find.byKey(const Key('grid-retry-button')), findsOneWidget);
      expect(find.text('hp-1-1'), findsNothing);
    });
  });
}
