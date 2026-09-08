import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/logging/debug_surface.dart';
import 'package:harness/shortcuts/app_shortcuts.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('shortcuts survive a focused terminal', () {
    // The whole design rests on this: the main pane is a real terminal that
    // takes the keyboard, and a shortcut bound above it has to still fire.
    // If xterm ever swallows ⌘ keys, every binding here goes silently dead.
    Future<int> pressWithTerminalFocused(
      WidgetTester tester,
      LogicalKeyboardKey key, {
      bool shift = false,
      bool alt = false,
      TargetPlatform? platform,
    }) async {
      // Off by default, and worth naming when it matters: a widget test runs as
      // Android unless told otherwise, so an Apple-gated branch in the terminal
      // is invisible here — which is exactly how ⌘ came to be the app's
      // modifier on macOS and the terminal's on Linux.
      debugDefaultTargetPlatformOverride = platform;
      var fired = 0;
      final terminal = Terminal();
      await tester.pumpWidget(
        MaterialApp(
          home: CallbackShortcuts(
            bindings: {
              SingleActivator(key, meta: true, shift: shift, alt: alt): () =>
                  fired++,
            },
            child: Scaffold(body: TerminalView(terminal, autofocus: true)),
          ),
        ),
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.alt);
      await tester.sendKeyEvent(key);
      if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
      return fired;
    }

    testWidgets('a plain ⌘ key reaches the binding', (tester) async {
      expect(
        await pressWithTerminalFocused(tester, LogicalKeyboardKey.keyN),
        1,
      );
    });

    testWidgets('⌘⇧ reaches the binding', (tester) async {
      expect(
        await pressWithTerminalFocused(
          tester,
          LogicalKeyboardKey.bracketRight,
          shift: true,
        ),
        1,
      );
    });

    testWidgets('a bracket chord reaches the binding', (tester) async {
      expect(
        await pressWithTerminalFocused(tester, LogicalKeyboardKey.bracketRight),
        1,
      );
    });

    testWidgets('⌘ + arrow reaches it too, on either desktop', (tester) async {
      // This used to read 0, with a note that xterm answers every arrow itself
      // so an arrow binding would be dead on arrival. That was never true of
      // the platform the app ships on: the terminal already let ⌘ chords go
      // past on macOS, and only there — the 0 was the Linux behaviour, seen
      // because a widget test runs as Android. Now the escape is uniform, so
      // pin it on both, arrows included: with ⌘ held, nothing reaches the pty.
      //
      // Arrows still go unbound in appShortcuts() ('no shortcut is bound to an
      // arrow key' below), but that is now a choice about what the hand expects
      // a terminal to do — not a limit on what can be bound.
      for (final platform in [TargetPlatform.macOS, TargetPlatform.linux]) {
        expect(
          await pressWithTerminalFocused(
            tester,
            LogicalKeyboardKey.arrowRight,
            platform: platform,
          ),
          1,
          reason: '⌘→ must not be answered by the terminal on $platform',
        );
        expect(
          await pressWithTerminalFocused(
            tester,
            LogicalKeyboardKey.arrowLeft,
            alt: true,
            platform: platform,
          ),
          1,
          reason: '⌘⌥← must not be answered by the terminal on $platform',
        );
      }
    });

    testWidgets('a bare key still goes to the terminal, not to a shortcut', (
      tester,
    ) async {
      // The other half of the contract: taking ⌘ must not cost the agent the
      // letters someone is typing at it.
      var fired = 0;
      final terminal = Terminal();
      final typed = <String>[];
      terminal.onOutput = typed.add;
      await tester.pumpWidget(
        MaterialApp(
          home: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.keyN): () => fired++,
            },
            child: Scaffold(body: TerminalView(terminal, autofocus: true)),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pump();

      expect(fired, 0, reason: 'the terminal must win a bare key');
    });
  });

  group('the declared set', () {
    test('no two shortcuts claim the same chord', () {
      final seen = <String>{};
      for (final shortcut in appShortcuts()) {
        final chord = describeShortcut(shortcut.activator);
        expect(seen.add(chord), isTrue, reason: '$chord is bound twice');
      }
    });

    test('nothing is bound with Control but the tab pair, or with Option alone', () {
      // Ctrl belongs to tmux and the shell; Option alone is how a terminal
      // sends Meta, which is why ⌥⏎ reaches the engine.
      //
      // ⌃⇥ / ⌃⇧⇥ are the single exception, and are pinned by CHORD rather than
      // waved through by action: the terminal is made to let exactly that pair
      // past (see terminal_view.dart) because no shell or tmux binding uses it,
      // and it is the pair every tabbed app trains people to reach for.
      // app_shortcuts.dart carries the full argument.
      //
      // By chord and not by trigger key, which is the stronger of the two ways
      // this has been written: "trigger is Tab, so Ctrl is allowed" would wave
      // ⌃⌥⇥ through as well, and the point of pinning is that a THIRD Ctrl
      // chord still fails.
      const ctrlAllowed = {'⌃⇥', '⌃⇧⇥'};
      for (final shortcut in appShortcuts()) {
        final chord = describeShortcut(shortcut.activator);
        if (shortcut.activator.control) {
          expect(
            ctrlAllowed.contains(chord),
            isTrue,
            reason: '${shortcut.label} takes a Ctrl key the shell needs',
          );
          // The Ctrl twin of a ⌘ chord, never both at once.
          expect(
            shortcut.activator.meta,
            isFalse,
            reason: '${shortcut.label} is the Ctrl twin of a ⌘ chord, not both',
          );
          continue;
        }
        expect(
          shortcut.activator.meta,
          isTrue,
          reason: '${shortcut.label} must be a ⌘ chord',
        );
      }
    });

    test('no shortcut is bound to an arrow key', () {
      final arrows = {
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
      };
      for (final shortcut in appShortcuts()) {
        expect(
          arrows.contains(shortcut.activator.trigger),
          isFalse,
          reason: '${shortcut.label} would be swallowed by the terminal',
        );
      }
    });

    test('does not take the three chords xterm already owns on macOS', () {
      const claimedByTerminal = {'⌘C', '⌘V', '⌘A'};
      for (final shortcut in appShortcuts()) {
        expect(
          claimedByTerminal.contains(describeShortcut(shortcut.activator)),
          isFalse,
          reason: '${shortcut.label} would steal copy/paste/select-all',
        );
      }
    });

    test('every declared shortcut gets a binding when a handler exists', () {
      final bindings = buildShortcutBindings(
        handlers: {for (final s in appShortcuts()) s.action: () {}},
        onSelectAgentIndex: (_) {},
      );
      expect(bindings.length, appShortcuts().length + kAgentDigitCount);
    });

    test(
      'a shortcut with no handler is left unbound, not bound to nothing',
      () {
        final bindings = buildShortcutBindings(handlers: const {});
        expect(bindings, isEmpty);
      },
    );
  });

  group('the rows the UI prints', () {
    test('two chords for one action are one row, not two', () {
      // ⌘] and ⌃⇥ both focus the next pane. Printed as two rows — which is
      // what the list did before it merged them — the screen reads as though
      // it forgot to collapse a duplicate.
      final rows = shortcutRows();
      final labels = rows.map((row) => row.label).toList();
      expect(labels.toSet().length, labels.length, reason: 'a label repeats');

      final next = rows.firstWhere((row) => row.label == 'Focus the next pane');
      expect(next.chords, [
        ['⌘', ']'],
        ['⌃', '⇥'],
      ]);
    });

    test('every declared shortcut reaches a row', () {
      final rows = shortcutRows();
      for (final shortcut in appShortcuts()) {
        final row = rows.firstWhere((row) => row.label == shortcut.label);
        expect(
          row.chords,
          contains(equals(describeShortcutKeys(shortcut.activator))),
          reason: '${shortcut.label} is bound but not printed',
        );
      }
    });

    test('the digits are one row, at the end of their own group', () {
      final rows = shortcutRows();
      final digits = rows.indexWhere(
        (row) => row.label == 'Jump to the 1st–9th agent',
      );
      expect(digits, isNot(-1));
      expect(rows[digits].chords, [
        ['⌘', '1 – 9'],
      ]);
      expect(rows[digits].group, ShortcutGroup.navigate);
      // Last of Navigate, so it does not split the group it belongs to.
      expect(rows[digits + 1].group, isNot(ShortcutGroup.navigate));
    });

    test('a chord is split into the keys a keyboard has', () {
      expect(
        describeShortcutKeys(
          const SingleActivator(
            LogicalKeyboardKey.bracketRight,
            meta: true,
            shift: true,
          ),
        ),
        ['⇧', '⌘', ']'],
      );
      // Tab prints as ⇥, the way a Mac menu prints it — `keyLabel` says 'Tab'.
      expect(
        describeShortcutKeys(
          const SingleActivator(LogicalKeyboardKey.tab, control: true),
        ),
        ['⌃', '⇥'],
      );
    });
  });

  group('the developer shortcut', () {
    // ⌘D opens Settings ▸ Debug. It is the one shortcut that is not always
    // there — a release build has no Debug screen — so what is guarded is that
    // the list and the build agree, in both directions.
    test(
      'is declared only where the debug surface is, and a test build is',
      () {
        expect(kDebugSurfaceEnabled, isTrue, reason: 'tests run in debug mode');
        expect(appShortcuts(), contains(kDebugShortcut));
        expect(kAppShortcuts, isNot(contains(kDebugShortcut)));
        expect(describeShortcut(kDebugShortcut.activator), '⌘D');
      },
    );

    test('reaches a binding and a printed row like any other', () {
      final bindings = buildShortcutBindings(
        handlers: {ShortcutAction.showDebug: () {}},
      );
      expect(bindings.containsKey(kDebugShortcut.activator), isTrue);
      expect(shortcutHintFor(ShortcutAction.showDebug), '⌘D');
      expect(
        shortcutRows().map((row) => row.label),
        contains(kDebugShortcut.label),
      );
    });
  });
}
