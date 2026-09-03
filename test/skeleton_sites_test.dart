// Every screen that waits on a call now waits in the SHAPE of its answer.
//
// These guard the property that makes a skeleton worth having and a spinner
// not: the placeholder occupies the same room as the content it stands in
// for, so nothing on the page moves when the answer lands. They also guard
// the two states that must never look alike — "still loading" and "answered
// with nothing" — which is the bug a bare empty list always has.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/core/models.dart';
import 'package:harness/grid/grid_network.dart';
import 'package:harness/grid/grid_networks_controller.dart';
import 'package:harness/grid/grid_selection_store.dart';
import 'package:harness/settings/sections/grid_network_table.dart';
import 'package:harness/settings/sections/grid_section.dart';
import 'package:harness/shared/theme/app_theme.dart';
import 'package:harness/shared/widgets/skeleton.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/widgets/machine_rail.dart';

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

/// A grid API that answers only when the test says so.
class _HeldGridApi extends FakeGridApi {
  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<GridMe> me() async {
    await _gate.future;
    return super.me();
  }
}

Widget _themed(Widget child) => MaterialApp(
  home: Builder(
    builder: (context) {
      AppTheme.brightness.value = Brightness.light;
      return BrightnessScope(child: Scaffold(body: child));
    },
  ),
);

const _machine = Machine(
  machineId: 'm-1',
  apiKey: '',
  authMode: MachineAuthMode.remote,
  name: 'prod-mac',
  status: 'online',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Settings ▸ Grid', () {
    testWidgets(
      'the table is a table before the grids arrive, and the strip is already '
      'real',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final api = _HeldGridApi();
        final controller = GridNetworksController(client: api);
        addTearDown(controller.dispose);
        final selection = GridSelectionStore(storage: _MemoryStore());

        await tester.pumpWidget(
          _themed(GridSection(controller: controller, selection: selection)),
        );
        await tester.pump();

        // The frame, the header and the way back to no grid at all are known
        // before the control plane answers, so they are drawn in ink.
        expect(find.byKey(const Key('grid-table-skeleton')), findsOneWidget);
        expect(find.text('GRID'), findsOneWidget);
        expect(find.text("Each engine's own login"), findsWidgets);
        // The strip reads the choice off disk, not the network.
        expect(find.text('NEW AGENTS USE'), findsOneWidget);
        // A count nobody knows yet is a bar, not the number 0.
        expect(find.byKey(const Key('grid-count-skeleton')), findsOneWidget);
        expect(find.text('2 grids'), findsNothing);

        final tableBefore = tester.getRect(
          find.byKey(const Key('grid-table-skeleton')),
        );
        final stripBefore = tester.getRect(find.text('NEW AGENTS USE'));

        api.release();
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('grid-table-skeleton')), findsNothing);
        expect(find.text('2 grids'), findsOneWidget);
        expect(find.text('hp-1-1'), findsOneWidget);
        // Nothing moved: the answer landed in the room the placeholder held.
        expect(tester.getRect(find.byType(GridNetworkTable)), tableBefore);
        expect(tester.getRect(find.text('NEW AGENTS USE')), stripBefore);
      },
    );
  });

  group('the machine rail', () {
    AppNotifier notifier() => AppNotifier(
      config: AppConfig.dev,
      authSession: AuthSession(),
      configStore: null,
    );

    testWidgets('an empty list that is still loading does not say "none"', (
      tester,
    ) async {
      final app = notifier()..status = AppStatus.authenticated;
      addTearDown(app.dispose);
      app.machinesLoading = true;

      await tester.pumpWidget(
        _themed(SizedBox(width: 320, child: MachineRail(notifier: app))),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('machines-loading')), findsOneWidget);
      // The sentence that means something else entirely.
      expect(find.text('no remote machines'), findsNothing);
    });

    testWidgets('an empty list that has answered says so', (tester) async {
      final app = notifier()..status = AppStatus.authenticated;
      addTearDown(app.dispose);

      await tester.pumpWidget(
        _themed(SizedBox(width: 320, child: MachineRail(notifier: app))),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('machines-loading')), findsNothing);
      expect(find.text('no remote machines'), findsOneWidget);
    });

    testWidgets('a placeholder machine row is the height of a real one', (
      tester,
    ) async {
      final loading = notifier()..status = AppStatus.authenticated;
      addTearDown(loading.dispose);
      loading.machinesLoading = true;
      await tester.pumpWidget(
        _themed(SizedBox(width: 320, child: MachineRail(notifier: loading))),
      );
      await tester.pump();
      final placeholder = tester
          .getRect(
            find
                .descendant(
                  of: find.byKey(const ValueKey('machines-loading')),
                  matching: find.byType(SkeletonText),
                )
                .first,
          )
          .height;

      final ready = notifier()..status = AppStatus.authenticated;
      addTearDown(ready.dispose);
      ready.machines = [_machine];
      ready.machineStates[_machine.machineId] = MachineState(_machine);
      await tester.pumpWidget(
        _themed(SizedBox(width: 320, child: MachineRail(notifier: ready))),
      );
      await tester.pump();

      // Rows are 36px boxes either way, so the rail does not resize under the
      // pointer when the list lands.
      expect(
        tester.getSize(find.text('prod-mac')).height,
        closeTo(placeholder, 0.01),
      );
    });
  });
}
