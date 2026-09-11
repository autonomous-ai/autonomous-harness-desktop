import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../state/app_state.dart';
import 'agents_page.dart';
import 'link_page.dart';
import 'terminal_page.dart';

/// Every phone page slides in the iOS way, and goes back with the edge swipe.
Route<void> phoneRoute(WidgetBuilder builder) =>
    CupertinoPageRoute<void>(builder: builder);

/// Where a tap on a machine goes. A machine this device holds no link to opens on ITS password
/// form — each machine has its own remote password — and only a linked one opens on its agents.
void openMachine(BuildContext context, AppNotifier notifier, String machineId) {
  final machine = notifier.stateOf(machineId);
  if (machine == null) return;
  Navigator.of(context).push(
    phoneRoute(
      (_) => machine.needsLink
          ? LinkPage(notifier: notifier, machineId: machineId)
          : AgentsPage(notifier: notifier, machineId: machineId),
    ),
  );
}

/// Opens one agent full screen.
///
/// ONE at a time, and that is the whole difference from the desktop grid: a phone has no room
/// for a second tile, so whatever else was open is closed rather than left attached somewhere
/// nobody can see it. The page goes up first and says it is attaching; the attach follows.
void openAgent(
  BuildContext context,
  AppNotifier notifier,
  String machineId,
  String agentId,
) {
  Navigator.of(context).push(
    phoneRoute(
      (_) => TerminalPage(
        notifier: notifier,
        machineId: machineId,
        agentId: agentId,
      ),
    ),
  );
  unawaited(_showOnly(notifier, machineId, agentId));
}

Future<void> _showOnly(
  AppNotifier notifier,
  String machineId,
  String agentId,
) async {
  await notifier.selectAgent(machineId, agentId);
  final keep = notifier.focusedPane?.id;
  for (final pane in [...notifier.panes]) {
    if (pane.id != keep) await notifier.closePane(pane.id);
  }
}
