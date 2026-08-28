import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
    }) async {
      var fired = 0;
      final terminal = Terminal();
      await tester.pumpWidget(
        MaterialApp(
          home: CallbackShortcuts(
            bindings: {
              SingleActivator(key, meta: true, shift: shift, alt: alt): () =>
                  fired++,
            },
            child: Scaffold(
              body: TerminalView(terminal, autofocus: true),
            ),
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
      return fired;
    }

    testWidgets('a plain ⌘ key reaches the binding', (tester) async {
      expect(await pressWithTerminalFocused(tester, LogicalKeyboardKey.keyN), 1);
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
        await pressWithTerminalFocused(
          tester,
          LogicalKeyboardKey.bracketRight,
        ),
        1,
      );
    });

    testWidgets('⌘ + arrow does NOT — which is why none is bound', (
      tester,
    ) async {
      // xterm turns every arrow into a terminal key and answers `handled`, so
      // a binding on one would be dead on arrival and the agent would get
      // cursor movement instead. Pinned so nobody adds an arrow shortcut and
      // spends an afternoon on why it does nothing.
      expect(
        await pressWithTerminalFocused(tester, LogicalKeyboardKey.arrowRight),
        0,
      );
      expect(
        await pressWithTerminalFocused(
          tester,
          LogicalKeyboardKey.arrowLeft,
          alt: true,
        ),
        0,
      );
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
      for (final shortcut in kAppShortcuts) {
        final chord = describeShortcut(shortcut.activator);
        expect(seen.add(chord), isTrue, reason: '$chord is bound twice');
      }
    });

    test('nothing is bound with Control, or with Option alone', () {
      // Ctrl belongs to tmux and the shell; Option alone is how a terminal
      // sends Meta, which is why ⌥⏎ reaches the engine.
      for (final shortcut in kAppShortcuts) {
        expect(
          shortcut.activator.control,
          isFalse,
          reason: '${shortcut.label} takes a Ctrl key the shell needs',
        );
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
      for (final shortcut in kAppShortcuts) {
        expect(
          arrows.contains(shortcut.activator.trigger),
          isFalse,
          reason: '${shortcut.label} would be swallowed by the terminal',
        );
      }
    });

    test('does not take the three chords xterm already owns on macOS', () {
      const claimedByTerminal = {'⌘C', '⌘V', '⌘A'};
      for (final shortcut in kAppShortcuts) {
        expect(
          claimedByTerminal.contains(describeShortcut(shortcut.activator)),
          isFalse,
          reason: '${shortcut.label} would steal copy/paste/select-all',
        );
      }
    });

    test('every declared shortcut gets a binding when a handler exists', () {
      final bindings = buildShortcutBindings(
        handlers: {for (final s in kAppShortcuts) s.action: () {}},
        onSelectAgentIndex: (_) {},
      );
      expect(bindings.length, kAppShortcuts.length + kAgentDigitCount);
    });

    test('a shortcut with no handler is left unbound, not bound to nothing', () {
      final bindings = buildShortcutBindings(handlers: const {});
      expect(bindings, isEmpty);
    });
  });
}
