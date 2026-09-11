import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../state/app_state.dart';
import 'agent_hero.dart';
import 'agents_page.dart';
import 'link_page.dart';
import 'terminal_page.dart';

/// Every phone page slides in the iOS way, and goes back with the edge swipe.
Route<void> phoneRoute(WidgetBuilder builder) =>
    CupertinoPageRoute<void>(builder: builder);

/// The route a terminal opens on: the row grows into the page's header, and nothing else moves.
///
/// ⚠️ **The page itself gets NO transition of its own, and that is the whole point.** A plain
/// [CupertinoPageRoute] slides the incoming page in from the right *while* the Hero flies the
/// header up out of the list — two motions in different directions, which is what makes a Hero
/// look like a piece escaping the transition. Fading the page instead is no better: the page
/// paints its own opaque background, so a fade is a full-screen rectangle changing opacity across
/// the flight, and the eye reads that as the screen flashing.
///
/// With no transition the page is simply *there*, under the flying header, and the only thing
/// moving is the header and the body rising under it ([AgentBodyReveal]).
///
/// Still a [CupertinoPageRoute] subclass so the edge-swipe back gesture survives — and the swipe
/// runs the Hero in reverse, which is the point of using one.
class _AgentPageRoute extends CupertinoPageRoute<void> {
  _AgentPageRoute({required super.builder});

  /// Matches the flight, so the route is finished exactly when the header lands.
  @override
  Duration get transitionDuration => kAgentHeroDuration;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

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
///
/// [heroSource] names the list this was opened from, so the engine mark's Hero tag matches the row
/// it is flying out of — see [agentHeroTag] for why the source has to be part of the tag at all.
void openAgent(
  BuildContext context,
  AppNotifier notifier,
  String machineId,
  String agentId, {
  required AgentHeroSource heroSource,
}) {
  Navigator.of(context).push(
    _AgentPageRoute(
      builder: (_) => TerminalPage(
        notifier: notifier,
        machineId: machineId,
        agentId: agentId,
        heroSource: heroSource,
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
