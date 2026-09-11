// The behavioural events: what people use, how long, and by which door.
//
// What is pinned here is the part a refactor breaks silently — that the door is
// carried and is the RIGHT door, and that every shortcut reports itself without
// anyone having to remember to add an event for it.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/analytics/analytics.dart';
import 'package:harness/analytics/analytics_events.dart';
import 'package:harness/shortcuts/app_shortcuts.dart';

/// Records instead of sending. The real queue is exercised in analytics_test.
class _Spy implements Analytics {
  final events = <({String name, Map<String, Object?> params})>[];

  @override
  void track(String name, {Map<String, Object?> params = const {}}) =>
      events.add((name: name, params: params));

  @override
  Future<void> close() async {}

  @override
  Future<void> flush() async {}

  Map<String, Object?> paramsOf(String name) =>
      events.firstWhere((e) => e.name == name).params;

  bool has(String name) => events.any((e) => e.name == name);
}

void main() {
  group('the shortcut funnel', () {
    test('every bound shortcut reports itself, with no per-key wiring', () {
      // The property that matters: a key bound LATER is measured the day it is
      // bound. buildShortcutBindings is the one place they are all wired, so
      // reporting from there is what makes that true.
      final seen = <String>[];
      final bindings = buildShortcutBindings(
        handlers: {for (final s in appShortcuts()) s.action: () {}},
        onUsed: (action, source) => seen.add('${action.name}/$source'),
      );
      for (final run in bindings.values) {
        run();
      }
      expect(seen, hasLength(appShortcuts().length));
    });

    test('the handler still runs, and the report comes first', () {
      final order = <String>[];
      final bindings = buildShortcutBindings(
        handlers: {ShortcutAction.newAgent: () => order.add('handler')},
        onUsed: (_, _) => order.add('report'),
      );
      bindings.values.first();
      // Reported before, so a handler that throws — or that opens a dialog and
      // never returns — still leaves a record that the key was pressed.
      expect(order, ['report', 'handler']);
    });

    test('with no reporter, bindings are the bare handlers', () {
      var ran = 0;
      final bindings = buildShortcutBindings(
        handlers: {ShortcutAction.newAgent: () => ran++},
      );
      bindings.values.first();
      expect(ran, 1);
    });

    test('the digits report too, under their own name', () {
      // They are deliberately not in appShortcuts() — nine near-identical rows
      // would bury the sheet — which is not a reason to leave them unmeasured.
      final seen = <String>[];
      final bindings = buildShortcutBindings(
        handlers: const {},
        onSelectPaneIndex: (_) {},
        onUsed: (action, source) => seen.add('${action.name}/$source'),
      );
      bindings.values.first();
      expect(seen.single, 'selectPaneByIndex/digit');
    });
  });

  group('shortcutSource — which SPELLING was pressed', () {
    // Every direction is bound both ways on purpose. Splitting the count is the
    // only way to answer whether that was worth doing; a combined figure says
    // nothing at all.
    test('hjkl is its own source', () {
      for (final key in [
        LogicalKeyboardKey.keyH,
        LogicalKeyboardKey.keyJ,
        LogicalKeyboardKey.keyK,
        LogicalKeyboardKey.keyL,
      ]) {
        expect(shortcutSource(SingleActivator(key, meta: true)), 'hjkl');
      }
    });

    test('the arrows are their own source', () {
      for (final key in [
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
      ]) {
        expect(shortcutSource(SingleActivator(key, meta: true)), 'arrow');
      }
    });

    test('everything else is just a shortcut', () {
      expect(
        shortcutSource(
          const SingleActivator(LogicalKeyboardKey.keyN, meta: true),
        ),
        'shortcut',
      );
    });
  });

  group('the events themselves', () {
    test('workspace_snapshot carries counts, never names', () {
      final spy = _Spy();
      spy.workspaceSnapshot(
        machinesLinked: 3,
        machinesOnline: 2,
        agentsTotal: 11,
        panesOpen: 4,
        railFolded: true,
        engines: ['codex', 'claude', 'claude'],
        layoutPreset: 'quad',
      );
      final p = spy.paramsOf('workspace_snapshot');
      expect(p['machines_linked'], 3);
      expect(p['agents_total'], 11);
      expect(p['panes_open'], 4);
      // Deduped AND sorted, so one desk reads as one value rather than as two
      // strings because a map iterated differently.
      expect(p['engines'], 'claude,codex');
    });

    test('turn_sent carries the door and not one character of the message', () {
      final spy = _Spy();
      spy.turnSent(engine: 'claude', source: 'palette');
      final p = spy.paramsOf('turn_sent');
      expect(p, {'engine': 'claude', 'source': 'palette'});
    });

    test('app_focus_time sends BOTH numbers', () {
      // Either alone is misleading for an app people leave open behind a
      // browser; the difference is the answer.
      final spy = _Spy();
      spy.appFocusTime(
        open: const Duration(hours: 8),
        focused: const Duration(minutes: 42),
      );
      final p = spy.paramsOf('app_focus_time');
      expect(p['open_seconds'], 28800);
      expect(p['focused_seconds'], 2520);
    });

    test('pane_closed says how long AND how much happened', () {
      // Same duration, different events: a tile worked in, and one opened,
      // looked at, and closed.
      final spy = _Spy();
      spy.paneClosed(engine: 'codex', secondsOpen: 600, turns: 0);
      expect(spy.paramsOf('pane_closed'), {
        'engine': 'codex',
        'seconds_open': 600,
        'turns': 0,
      });
    });

    test('task_routed carries the RANK, which is the whole point', () {
      // A router that is right prints rank 0; one whose third suggestion is the
      // one people take prints 2, and nothing else in the product would say so.
      final spy = _Spy();
      spy.taskRouted(
        outcome: 'picked',
        candidates: 8,
        chosenRank: 3,
        confidence: 0.42,
        via: 'backend',
      );
      final p = spy.paramsOf('task_routed');
      expect(p['chosen_rank'], 3);
      expect(p['candidates'], 8);
      expect(p['confidence'], 0.42);
      // No task text, and no length of it either.
      expect(p.keys, isNot(contains('task')));
      expect(p.keys, isNot(contains('chars')));
    });

    test('task_routed rounds confidence to the side of the threshold', () {
      final spy = _Spy();
      spy.taskRouted(
        outcome: 'auto',
        candidates: 2,
        chosenRank: 0,
        confidence: 0.8549999,
        via: 'backend',
      );
      expect(spy.paramsOf('task_routed')['confidence'], 0.85);
    });

    test('abandoned is rank -1, not a missing event', () {
      // A router whose list gets closed fails in a way that looks, in `picked`
      // counts alone, exactly like a router nobody opens.
      final spy = _Spy();
      spy.taskRouted(
        outcome: 'abandoned',
        candidates: 5,
        chosenRank: -1,
        confidence: 0.3,
        via: 'heuristic',
      );
      expect(spy.paramsOf('task_routed')['chosen_rank'], -1);
    });

    test('the update funnel is three events, not one', () {
      // The DROPS between them are the finding: an "installed" count alone
      // cannot show how many people were offered it and said no.
      final spy = _Spy();
      spy.updateOffered(from: '1.1.6', to: '1.1.7');
      spy.updateSkipped(from: '1.1.6', to: '1.1.7');
      spy.updateInstalled(from: '1.1.6', to: '1.1.7');
      expect(spy.has('update_offered'), isTrue);
      expect(spy.has('update_skipped'), isTrue);
      expect(spy.paramsOf('update_installed'), {
        'from': '1.1.6',
        'to': '1.1.7',
      });
    });

    test('machine events carry a mode, never a name', () {
      final spy = _Spy();
      spy.machineLinked(mode: 'remote');
      spy.machineUnlinked();
      expect(spy.paramsOf('machine_linked'), {'mode': 'remote'});
      expect(spy.paramsOf('machine_unlinked'), isEmpty);
    });

    test('feature_used is one event with a controlled vocabulary', () {
      final spy = _Spy();
      spy.featureUsed(feature: ShortcutAction.switchAgent.name, source: 'hjkl');
      expect(spy.paramsOf('feature_used'), {
        'feature': 'switchAgent',
        'source': 'hjkl',
      });
    });
  });
}
