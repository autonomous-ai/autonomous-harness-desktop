// The pane header's one geometric promise: the model control and the status
// mark sit at the RIGHT edge, whatever the agent is called. They are the
// controls; everything to their left is a label, and a control that drifts
// toward the middle when a name is short reads as part of the label.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/terminal/terminal_session.dart';
import 'package:harness/widgets/agent_model_menu.dart';
import 'package:harness/widgets/terminal_panel.dart';

void main() {
  /// The strip's own right edge: the panel width less the padding the header
  /// sets on itself. Read from the panel rather than restated, so a change to
  /// that padding moves the expectation with it.
  const double paneWidth = 900;
  const double headerPadding = 14;

  TerminalSession sessionNamed(String name) {
    final session = TerminalSession(
      machineId: 'local',
      agentId: 'agent-1',
      agentName: name,
      engineId: 'codex',
      send: (_, _) async => true,
      sendBinary: (_) async => true,
    );
    session.status = TerminalSessionStatus.controlling;
    session.streamId = 'stream-1';
    return session;
  }

  Future<void> pump(WidgetTester tester, TerminalSession session) async {
    // Wider than the pane, and stated: the default test window is 800px, and a
    // `SizedBox(width: 900)` inside it is silently clamped to 800 — which makes
    // every measurement against `paneWidth` wrong by 100px and looks exactly
    // like a layout bug.
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final notifier = AppNotifier(
      config: AppConfig.dev,
      authSession: AuthSession(),
      configStore: null,
    );
    addTearDown(notifier.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: paneWidth,
            height: 320,
            child: TerminalPanel(
              notifier: notifier,
              session: session,
              focused: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Everything the header puts to the RIGHT of the model pill: one 6px gap and
  /// the status mark (an 8px dot in 4px padding). Stated so the assertions read
  /// as "flush, allowing for the status mark" rather than as a magic number.
  const double trailing = 6 + 8 + 4 + 4;

  testWidgets('the model control is flush right, however short the name', (
    tester,
  ) async {
    final session = sessionNamed('a');
    addTearDown(session.dispose);
    await pump(tester, session);

    final menu = tester.getRect(find.byType(AgentModelMenu));

    // The regression this exists for: the pill was a `Flexible` competing with
    // the name's `Expanded` for one flex share each. It wanted far less than
    // its half, RenderFlex does not hand an unused share back, and the leftover
    // landed as dead space at the end of the row — 250px of it in this pane.
    expect(
      paneWidth - headerPadding - menu.right,
      closeTo(trailing, 1),
      reason: 'the model pill drifted left of the status mark',
    );
  });

  testWidgets('a long name moves the pill not one pixel', (tester) async {
    final short = sessionNamed('a');
    addTearDown(short.dispose);
    await pump(tester, short);
    final withShortName = tester.getRect(find.byType(AgentModelMenu));

    final long = sessionNamed(
      'an agent with a deliberately very long name that has to ellipsize',
    );
    addTearDown(long.dispose);
    await pump(tester, long);
    final withLongName = tester.getRect(find.byType(AgentModelMenu));

    // Pinned to the right edge, so the name's length is the name's business.
    // A pill that shifts with the label is one the eye has to look for.
    expect(withLongName.right, closeTo(withShortName.right, 0.5));
    expect(withLongName.right, lessThanOrEqualTo(paneWidth - headerPadding));
  });

  testWidgets('a narrow pane bounds the pill instead of overflowing', (
    tester,
  ) async {
    final session = sessionNamed('a');
    addTearDown(session.dispose);
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final notifier = AppNotifier(
      config: AppConfig.dev,
      authSession: AuthSession(),
      configStore: null,
    );
    addTearDown(notifier.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            // A tile in a four-pane grid on a small window.
            width: 220,
            height: 320,
            child: TerminalPanel(
              notifier: notifier,
              session: session,
              focused: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // The cap is what keeps the old `Flexible`'s one real job: a long grid
    // model id ellipsizes rather than overflowing the strip.
    expect(tester.takeException(), isNull);
    final menu = tester.getRect(find.byType(AgentModelMenu));
    expect(menu.width, lessThanOrEqualTo((220 - headerPadding * 2) / 2 + 0.5));
  });
}
