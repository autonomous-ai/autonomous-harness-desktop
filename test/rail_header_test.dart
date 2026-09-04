import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/models.dart';
import 'package:harness/shared/theme/app_theme.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/widgets/machine_rail.dart';

/// The rail's head is a toolbar: its own surface, its own bottom edge, and the
/// filter box inside it rather than behind a button.
///
/// What these hold: the filter is always there (it used to be a toggle, which
/// is what made ⌘F "open" something), the ✕ only exists once there is something
/// to clear, and the toolbar keeps its two buttons far enough apart to read as
/// two.
void main() {
  const machine = Machine(
    machineId: 'machine-1',
    apiKey: '',
    authMode: MachineAuthMode.remote,
    name: 'prod-mac',
    status: 'online',
  );

  AppNotifier railNotifier() {
    final notifier = AppNotifier(
      config: AppConfig.dev,
      authSession: AuthSession(),
      configStore: null,
    );
    final state = MachineState(machine)
      ..connectionStatus = ConnectionStatus.connected
      ..terminalCapabilityLoaded = true
      ..terminalCapabilityAvailable = true
      ..agentLoadStatus = AgentLoadStatus.loaded
      ..agents = [
        Agent.fromJson({
          'id': 'a',
          'sessionId': 'session-a',
          'name': 'Ban làm được gì',
          'engine': 'claude',
          'status': 'active',
          'terminal': {
            'runtimes': [
              {'backend': 'tmux', 'paneId': '%1'},
            ],
          },
        }),
        Agent.fromJson({
          'id': 'b',
          'sessionId': 'session-b',
          'name': 'Claude Code',
          'engine': 'claude',
          'status': 'active',
          'terminal': {
            'runtimes': [
              {'backend': 'tmux', 'paneId': '%2'},
            ],
          },
        }),
      ];
    notifier.machines = [machine];
    notifier.machineStates[machine.machineId] = state;
    notifier.expandedMachines.add(machine.machineId);
    return notifier;
  }

  Future<GlobalKey<MachineRailState>> pumpRail(
    WidgetTester tester,
    AppNotifier notifier, {
    double width = 264,
  }) async {
    final key = GlobalKey<MachineRailState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            child: MachineRail(
              key: key,
              notifier: notifier,
              onCollapse: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return key;
  }

  testWidgets('the filter is part of the toolbar, not behind a button', (
    tester,
  ) async {
    final notifier = railNotifier();
    await pumpRail(tester, notifier);

    // Drawn without being asked for. The magnifier that used to swap this box
    // in and out is gone with it — a button whose whole job was hiding a 30px
    // control, at the cost of changing the rail's height on a click.
    expect(find.byKey(const Key('rail-filter-field')), findsOneWidget);
    expect(find.text('Filter machines and agents'), findsOneWidget);
    expect(find.byTooltip('Clear filter'), findsNothing);
    notifier.dispose();
  });

  testWidgets('⌘F puts the caret in the filter instead of opening it', (
    tester,
  ) async {
    final notifier = railNotifier();
    final key = await pumpRail(tester, notifier);

    key.currentState!.openFilter();
    await tester.pump();

    final field = tester.widget<TextField>(
      find.byKey(const Key('rail-filter-field')),
    );
    expect(field.focusNode?.hasFocus, isTrue);
    notifier.dispose();
  });

  testWidgets('typing narrows the list, and ✕ gives it back', (tester) async {
    final notifier = railNotifier();
    await pumpRail(tester, notifier);

    // 'Code', not 'Claude': the filter also reads an agent's ENGINE, and both
    // of these run Claude — a query that matched the engine would narrow to
    // nothing and prove nothing.
    await tester.enterText(find.byKey(const Key('rail-filter-field')), 'Code');
    await tester.pump();

    expect(find.text('Claude Code'), findsOneWidget);
    expect(find.text('Ban làm được gì'), findsNothing);

    // The ✕ arrives with something to clear, and not before.
    final clear = find.byTooltip('Clear filter');
    expect(clear, findsOneWidget);
    await tester.tap(clear);
    await tester.pump();

    expect(find.text('Ban làm được gì'), findsOneWidget);
    expect(find.byTooltip('Clear filter'), findsNothing);
    notifier.dispose();
  });

  testWidgets('the filter sits DOWN in the toolbar, not up out of it', (
    tester,
  ) async {
    final notifier = railNotifier();
    await pumpRail(tester, notifier);

    // Three layers, in this order: the list, the toolbar raised off it, and the
    // field cut back down to the list's own level. `AppSurface.recess` raises a
    // surface off its ground in BOTH themes — it lightens in dark and darkens
    // in light — so painting the field with it a second time built the field up
    // out of the toolbar instead, which is the inversion this catches.
    final field = tester.widget<TextField>(
      find.byKey(const Key('rail-filter-field')),
    );
    expect(field.decoration?.fillColor, AppGlass.sidebarFill);
    expect(field.decoration?.fillColor, isNot(AppSurface.recess));
    notifier.dispose();
  });

  testWidgets('the toolbar keeps its two buttons apart, and its bottom edge', (
    tester,
  ) async {
    final notifier = railNotifier();
    await pumpRail(tester, notifier);

    // 2px between glyphs was the old spacing and it read as one smudge. The
    // gap is measured between the buttons' boxes, so it survives a change of
    // glyph size.
    final reload = tester.getRect(find.byTooltip('Reload machines  ⌘R'));
    final collapse = tester.getRect(find.byTooltip('Collapse sidebar  ⌘\\'));
    expect(collapse.left - reload.right, greaterThanOrEqualTo(6));

    // The list starts below the toolbar's rule, not level with it — the whole
    // point of the block is that the head is not the first row of the rail.
    expect(
      tester.getTopLeft(find.text('prod-mac')).dy,
      greaterThan(reload.bottom),
    );
    notifier.dispose();
  });
}
