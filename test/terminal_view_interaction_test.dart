import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:xterm/src/ui/custom_text_edit.dart';

void main() {
  test('does not turn an xterm keyboard command into text styling', () {
    final terminal = Terminal(maxLines: 20, reflowEnabled: false)
      ..resize(80, 4);
    terminal.buffer.clear();
    final cell = CellData.empty();

    // `CSI > 4 ; 2 m` configures xterm's modifyOtherKeys mode. It is not SGR
    // `CSI 4 ; 2 m`, which would mean underline + faint.
    terminal.write('\x1b[>4;2mtyped');

    expect(terminal.cursor.attrs, 0);
    terminal.buffer.currentLine.getCellData(4, cell);
    expect(cell.flags, 0);
  });

  test('keeps ordinary SGR styling intact', () {
    final terminal = Terminal(maxLines: 20, reflowEnabled: false)
      ..resize(80, 4);
    terminal.buffer.clear();
    final cell = CellData.empty();

    terminal.write('\x1b[4;2mstyled');

    expect(terminal.cursor.attrs, CellAttr.underline | CellAttr.faint);
    terminal.buffer.currentLine.getCellData(5, cell);
    expect(cell.flags, CellAttr.underline | CellAttr.faint);
  });

  test('SGR 22 clears bold and faint across live write chunks', () {
    final terminal = Terminal(maxLines: 20, reflowEnabled: false)
      ..resize(80, 4);
    terminal.buffer.clear();
    final cell = CellData.empty();

    // tmux control mode can deliver the reset in a later output frame than
    // the styled text. The parser must retain stream state across writes while
    // still applying SGR 22 exactly like a native terminal.
    terminal.write('\x1b[1;2mB');
    terminal.write('\x1b[22mN');

    terminal.buffer.currentLine.getCellData(0, cell);
    expect(cell.flags, CellAttr.bold | CellAttr.faint);
    terminal.buffer.currentLine.getCellData(1, cell);
    expect(cell.flags, 0);
    expect(terminal.cursor.attrs, 0);
  });

  testWidgets('commits IME text once and never forwards its pre-edit keys', (
    tester,
  ) async {
    final terminal = Terminal(maxLines: 200, reflowEnabled: false)
      ..resize(80, 12);
    final outbound = <String>[];
    terminal.onOutput = outbound.add;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 260,
            child: TerminalView(terminal, autofocus: true),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.testTextInput.hasAnyClients, isTrue);

    // The raw key that begins a Pinyin/Japanese/Vietnamese composition must
    // reach the native text input client, not the PTY.
    final handled = await tester.sendKeyDownEvent(
      LogicalKeyboardKey.keyN,
      character: 'n',
      platform: 'macos',
    );
    expect(handled, isFalse);
    expect(outbound, isEmpty);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'ni',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await tester.pump();
    expect(outbound, isEmpty);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'に',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    await tester.pump();
    expect(outbound, ['に']);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'にnihao',
        selection: TextSelection.collapsed(offset: 6),
        composing: TextRange(start: 1, end: 6),
      ),
    );
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'に你好',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    await tester.pump();
    expect(outbound, ['に', '你好']);

    // Cancelling a composition must not insert an empty or partial value.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'に你好telex',
        selection: TextSelection.collapsed(offset: 8),
        composing: TextRange(start: 3, end: 8),
      ),
    );
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'に你好',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    await tester.pump();
    expect(outbound, ['に', '你好']);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'に你好Tiếng Việt 日本語 中文',
        selection: TextSelection.collapsed(offset: 20),
      ),
    );
    await tester.pump();
    expect(outbound, ['に', '你好', 'Tiếng Việt 日本語 中文']);
  });

  testWidgets('rewrites Telex text without losing IME context', (tester) async {
    final terminal = Terminal(maxLines: 200, reflowEnabled: false)
      ..resize(80, 12);
    final outbound = <String>[];
    terminal.onOutput = outbound.add;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 260,
            child: TerminalView(terminal, autofocus: true),
          ),
        ),
      ),
    );
    await tester.pump();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'u',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'ư',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    await tester.pump();

    expect(outbound, ['u', '\x7f', 'ư']);

    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.enter,
      character: '\r',
      platform: 'macos',
    );
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'a',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    await tester.pump();
    expect(outbound, ['u', '\x7f', 'ư', '\r', 'a']);
  });

  testWidgets('replays the suffix when native text replaces an earlier vowel', (
    tester,
  ) async {
    final terminal = Terminal(maxLines: 200, reflowEnabled: false)
      ..resize(80, 12);
    final outbound = <String>[];
    terminal.onOutput = outbound.add;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 260,
            child: TerminalView(terminal, autofocus: true),
          ),
        ),
      ),
    );
    await tester.pump();

    for (final value in const [
      TextEditingValue(
        text: 'o',
        selection: TextSelection.collapsed(offset: 1),
      ),
      TextEditingValue(
        text: 'ô',
        selection: TextSelection.collapsed(offset: 1),
      ),
      TextEditingValue(
        text: 'ôi',
        selection: TextSelection.collapsed(offset: 2),
      ),
      TextEditingValue(
        text: 'ối',
        selection: TextSelection.collapsed(offset: 2),
      ),
    ]) {
      tester.testTextInput.updateEditingValue(value);
      await tester.pump();
    }

    // The native input source owns `oois -> ối`. The terminal bridge only
    // applies the successive text states and contains no Telex conversion.
    expect(outbound, ['o', '\x7f', 'ô', 'i', '\x7f', '\x7f', 'ối']);
  });

  testWidgets('does not forward marked text before the IME commits it', (
    tester,
  ) async {
    final terminal = Terminal(maxLines: 200, reflowEnabled: false)
      ..resize(80, 12);
    final outbound = <String>[];
    terminal.onOutput = outbound.add;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 260,
            child: TerminalView(terminal, autofocus: true),
          ),
        ),
      ),
    );
    await tester.pump();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'ni',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await tester.pump();
    expect(outbound, isEmpty);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '你',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    await tester.pump();

    expect(outbound, ['你']);
  });

  testWidgets('does not preview a marked buffer already mirrored to the PTY', (
    tester,
  ) async {
    final terminal = Terminal(maxLines: 200, reflowEnabled: false)
      ..resize(80, 12);
    final outbound = <String>[];
    terminal.onOutput = outbound.add;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 260,
            child: TerminalView(terminal, autofocus: true),
          ),
        ),
      ),
    );
    await tester.pump();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'xin chaf banj nha',
        selection: TextSelection.collapsed(offset: 17),
      ),
    );
    await tester.pump();
    expect(outbound, ['xin chaf banj nha']);

    // Some macOS input sources immediately mark the same full buffer again.
    // It is not new pre-edit text and must not leave a composing overlay.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'xin chaf banj nha',
        selection: TextSelection.collapsed(offset: 17),
        composing: TextRange(start: 0, end: 17),
      ),
    );
    await tester.pump();

    expect(outbound, ['xin chaf banj nha']);
  });

  testWidgets(
    'clears an IME preview as soon as the remote terminal echoes it',
    (tester) async {
      final terminal = Terminal(maxLines: 200, reflowEnabled: false)
        ..resize(80, 12);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 260,
              child: TerminalView(terminal, autofocus: true),
            ),
          ),
        ),
      );
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'sdfjkhs',
          selection: TextSelection.collapsed(offset: 7),
          composing: TextRange(start: 0, end: 7),
        ),
      );
      await tester.pump();
      final state = tester.state<TerminalViewState>(find.byType(TerminalView));
      expect(state.debugComposingText, 'sdfjkhs');

      // This is an incoming terminal write, not a local TextInput commit.
      terminal.write('> sdfjkhs');
      await tester.pump();

      expect(state.debugComposingText, isNull);
    },
  );

  testWidgets('clears native editing state when switching terminals', (
    tester,
  ) async {
    final first = Terminal(maxLines: 200, reflowEnabled: false)..resize(80, 12);
    final second = Terminal(maxLines: 200, reflowEnabled: false)
      ..resize(80, 12);
    final active = ValueNotifier<Terminal>(first);
    addTearDown(active.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 260,
            child: ValueListenableBuilder<Terminal>(
              valueListenable: active,
              builder: (_, terminal, _) =>
                  TerminalView(terminal, autofocus: true),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'ni',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await tester.pump();

    active.value = second;
    await tester.pump();
    await tester.pump();

    expect(tester.testTextInput.editingState?['text'], isEmpty);
  });

  testWidgets('coalesces an IME replacement with its queued delete selector', (
    tester,
  ) async {
    final terminal = Terminal(maxLines: 200, reflowEnabled: false)
      ..resize(80, 12);
    final outbound = <String>[];
    terminal.onOutput = outbound.add;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 260,
            child: TerminalView(terminal, autofocus: true),
          ),
        ),
      ),
    );
    await tester.pump();

    final input = tester.state<CustomTextEditState>(
      find.byType(CustomTextEdit),
    );
    input.updateEditingValue(
      const TextEditingValue(
        text: 'u',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    input.performSelector('deleteBackward:');
    input.updateEditingValue(
      const TextEditingValue(
        text: 'ư',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    await tester.pump();

    expect(outbound, ['u', '\x7f', 'ư']);
  });

  testWidgets('keeps Backspace as a terminal control key', (tester) async {
    final terminal = Terminal(maxLines: 200, reflowEnabled: false)
      ..resize(80, 12);
    final outbound = <String>[];
    terminal.onOutput = outbound.add;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 260,
            child: TerminalView(terminal, autofocus: true),
          ),
        ),
      ),
    );
    await tester.pump();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'u',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    await tester.pump();

    final handled = await tester.sendKeyDownEvent(
      LogicalKeyboardKey.backspace,
      character: '\b',
      platform: 'macos',
    );

    expect(handled, isFalse);
    tester
        .state<CustomTextEditState>(find.byType(CustomTextEdit))
        .performSelector('deleteBackward:');
    await tester.pump(const Duration(milliseconds: 1));
    expect(outbound, ['u', '\x7f']);
  });

  testWidgets(
    'mouse wheel scrolls synthesized tmux history without PTY input',
    (tester) async {
      final terminal = Terminal(maxLines: 200, reflowEnabled: false)
        ..resize(80, 12);
      final outbound = <String>[];
      terminal.onOutput = outbound.add;
      final history = List.generate(
        80,
        (index) => '\x1b[${index.isEven ? 31 : 36}mhistory-$index\x1b[0m\r\n',
      ).join();
      final viewportPush = List.filled(12, '\r\n').join();
      terminal.write(
        '\x1bc\x1b[?25l\x1b[?7l\x1b[H\x1b[2J'
        '$history$viewportPush\x1b[H\x1b[2J'
        '\x1b[1;1Hcurrent-screen\x1b[0m'
        '\x1b[1;15H\x1b[?7h\x1b[?25h',
      );
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 260,
              child: TerminalView(
                terminal,
                scrollController: scrollController,
                autofocus: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(scrollController.hasClients, isTrue);
      final bottom = scrollController.position.maxScrollExtent;
      expect(bottom, greaterThan(0));
      scrollController.jumpTo(bottom);

      final position = tester.getCenter(find.byType(TerminalView));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: position,
          scrollDelta: const Offset(0, -120),
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.pumpAndSettle();

      expect(scrollController.offset, lessThan(bottom));
      expect(terminal.buffer.getText(), contains('history-0'));
      expect(outbound, isEmpty);
    },
  );
}
