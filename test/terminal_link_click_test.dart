import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/terminal/terminal_session.dart';
import 'package:harness/widgets/terminal_panel.dart';
import 'package:xterm/xterm.dart';

const _url = 'https://example.com/q/1';

/// A pane printing `see <url> now` — the URL on columns 4 to 26 — with mouse
/// reporting ON, which is how every agent pane arrives: the CLI sets tmux
/// `mouse on`, and xterm then hands a plain tap to the program rather than to
/// `TerminalView.onTapUp`.
Future<List<Uri>> _pane(WidgetTester tester) async {
  final opened = <Uri>[];
  final session = TerminalSession(
    machineId: 'local',
    agentId: 'a',
    agentName: 'a',
    engineId: 'claude',
    send: (_, _) async => true,
    sendBinary: (_) async => true,
  );
  session.status = TerminalSessionStatus.controlling;
  session.streamId = 'stream-a';
  final notifier = AppNotifier(
    config: AppConfig.dev,
    authSession: AuthSession(),
    configStore: null,
  );
  addTearDown(() {
    session.dispose();
    notifier.dispose();
  });

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 900,
          height: 320,
          child: TerminalPanel(
            notifier: notifier,
            session: session,
            focused: true,
            onOpenLink: opened.add,
          ),
        ),
      ),
    ),
  );
  session.terminal.write('\x1b[?1000h\x1b[?1006h');
  session.terminal.write('see $_url now');
  await tester.pump();
  return opened;
}

/// The middle of cell [x] on the first row, in global coordinates.
Offset _cellCenter(WidgetTester tester, int x) {
  final render = tester
      .state<TerminalViewState>(find.byType(TerminalView))
      .renderTerminal;
  final cell = render.cellSize;
  return render.localToGlobal(
    render.getOffset(CellOffset(x, 0)) +
        Offset(cell.width / 2, cell.height / 2),
  );
}

/// Clicks the middle of cell [x] on the first row, holding [holding] if given.
Future<void> _click(
  WidgetTester tester,
  int x, {
  LogicalKeyboardKey? holding,
}) async {
  if (holding != null) await tester.sendKeyDownEvent(holding);
  await tester.tapAt(_cellCenter(tester, x));
  if (holding != null) await tester.sendKeyUpEvent(holding);
  // Past xterm's own 300ms wait for a second tap (it cannot know yet whether
  // this was one click or the first of a double) — and, with mouse reporting
  // on, past the short timer TerminalSession batches the forwarded click on.
  await tester.pump(const Duration(milliseconds: 400));
}

/// A mouse resting on cell [x] of the first row.
Future<TestGesture> _hover(WidgetTester tester, int x) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(_cellCenter(tester, x));
  await tester.pump();
  return mouse;
}

TerminalView _view(WidgetTester tester) =>
    tester.widget<TerminalView>(find.byType(TerminalView));

void main() {
  testWidgets('⌘-click opens the link under the pointer', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final opened = await _pane(tester);
      await _click(tester, 8, holding: LogicalKeyboardKey.meta);
      expect(opened, [Uri.parse(_url)]);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('a plain click on a link is left to the terminal', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final opened = await _pane(tester);
      await _click(tester, 8);
      expect(opened, isEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('⌘-click beside a link opens nothing', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final opened = await _pane(tester);
      await _click(tester, 1, holding: LogicalKeyboardKey.meta);
      expect(opened, isEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  // Ctrl, the modifier paste already uses there: ⌘ is the terminal's on Linux.
  testWidgets('on Linux, Ctrl-click opens the link', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final opened = await _pane(tester);
      await _click(tester, 8, holding: LogicalKeyboardKey.control);
      expect(opened, [Uri.parse(_url)]);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('holding ⌘ over a link shows a hand and marks the link', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await _pane(tester);
      await _hover(tester, 8);
      expect(_view(tester).mouseCursor, SystemMouseCursors.text);
      expect(_view(tester).controller!.highlights, isEmpty);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.pump();
      expect(_view(tester).mouseCursor, SystemMouseCursors.click);
      expect(_view(tester).controller!.highlights, hasLength(1));

      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pump();
      expect(_view(tester).mouseCursor, SystemMouseCursors.text);
      expect(_view(tester).controller!.highlights, isEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('the hand goes when the pointer leaves the link', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await _pane(tester);
      final mouse = await _hover(tester, 8);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.pump();

      await mouse.moveTo(_cellCenter(tester, 1));
      await tester.pump();
      expect(_view(tester).mouseCursor, SystemMouseCursors.text);
      expect(_view(tester).controller!.highlights, isEmpty);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
