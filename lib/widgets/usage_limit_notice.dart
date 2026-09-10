import 'dart:async';

import 'package:flutter/material.dart';

import '../analytics/analytics.dart';
import '../grid/grid_selection_store.dart';
import '../grid/grid_surface.dart';
import '../logging/app_log.dart';
import '../logging/debug_surface.dart';
import '../shared/theme/app_theme.dart' as grid;
import '../state/app_state.dart';
import '../usage/usage_controller.dart';
import '../usage/usage_nudge_store.dart';
import '../usage/usage_offer.dart';
import '../usage/usage_pressure.dart';
import '../usage/usage_window.dart';
import 'usage_limit_card.dart';
import 'usage_offer_actions.dart';

/// The one thing this app says about a subscription without being asked.
///
/// A card above the status rail, at the bottom-left corner — a hand's width
/// from the amber figure it is about, so the sentence and the number read as
/// one statement rather than two.
///
/// **Three deliberate restraints**, because an unprompted message is the most
/// expensive thing an app can spend:
///
///  * **Not a dialog.** These panes are terminals. A modal takes keyboard focus
///    away from whichever one has it, so keystrokes meant for a running agent
///    land nowhere — and 90% of a window arrives precisely when somebody is
///    deep in a turn, which is the worst moment to be interrupted.
///  * **Not full-bleed.** It floats over a corner instead of taking a row of
///    layout, because a strip in the [Column] would resize every pane on this
///    screen — a real SIGWINCH to every pty, and a tmux redraw, for a message.
///  * **Once per window.** Closing it writes the window's key to
///    [UsageNudgeStore] until that window resets. The poll behind it runs every
///    sixty seconds, so without that the card would come back a minute after
///    being closed, which is how people learn to dismiss a warning unread.
///
/// And it never draws without something to press: `resolveUsageOffer` answers null
/// wherever the only honest content would be a restatement of the figure.
class UsageLimitNotice extends StatefulWidget {
  const UsageLimitNotice({
    super.key,
    required this.notifier,
    required this.usage,
    @visibleForTesting this.nudges,
    @visibleForTesting this.selection,
    @visibleForTesting this.gridSurface = kGridSurfaceEnabled,
  });

  final AppNotifier notifier;

  /// The accounts' rate limits — the SAME controller the status rail draws, so
  /// the card and the figure under it can never be one poll apart.
  final UsageController usage;

  /// Injected by tests so a run never reads the developer's own `state.json`.
  final UsageNudgeStore? nudges;
  final GridSelectionStore? selection;

  /// Whether this build has providers at all. A compile-time const in the app,
  /// taken as a parameter so the shipped build's own behaviour — no card,
  /// because there is nothing behind it — can be asserted from a test run,
  /// where it is always true.
  final bool gridSurface;

  /// How far the card floats above the status rail, and in from the window's
  /// left edge.
  static const double inset = 12;

  @override
  State<UsageLimitNotice> createState() => _UsageLimitNoticeState();
}

class _UsageLimitNoticeState extends State<UsageLimitNotice> {
  /// The alerts already counted as shown, so `usage_limit_warned` reports
  /// occasions rather than the once-a-minute poll that redraws them.
  final _reported = <String>{};

  UsageNudgeStore get _nudges => widget.nudges ?? usageNudgeStore;
  GridSelectionStore get _selection => widget.selection ?? gridSelectionStore;

  /// Nothing is offered again until this moment.
  ///
  /// ⚠️ Set by a dismissal, and it is not politeness. Two accounts can be over
  /// the threshold at once, and closing the first one used to put the second
  /// one on screen **in the same place, under the pointer that had just
  /// clicked** — so a second click landed on a card nobody had read. A person
  /// who has just said "not now" is not asking to be asked again this second.
  ///
  /// No timer behind it: the poll rebuilds this once a minute anyway, so the
  /// next alert arrives on its own. A cool-off that needed a `Timer` would be a
  /// second thing to cancel in [dispose] for no gain.
  DateTime? _quietUntil;

  /// The last silence explained, so [_explain] says it once rather than on
  /// every rebuild — this widget rebuilds with the whole shell, which is often.
  String? _lastSilence;

  /// The window worth speaking about right now, and what to offer for it.
  ///
  /// The alerts are walked in order rather than reduced to the tightest one:
  /// with the session window closed for this cycle, a weekly window at 94% is
  /// still worth saying, and picking first would have thrown it away.
  UsageOffer? get _offer {
    final quietUntil = _quietUntil;
    if (quietUntil != null && DateTime.now().isBefore(quietUntil)) return null;
    final blocked = <String>[];
    for (final alert in usageAlerts(widget.usage.readings)) {
      if (_nudges.isDismissed(alert.key)) {
        blocked.add('${alert.key}: dismissed until this window resets');
        continue;
      }
      final resolved = usageOfferOf(
        widget.notifier,
        alert,
        gridSurface: widget.gridSurface,
        selection: _selection,
      );
      if (resolved.offer != null) return resolved.offer;
      blocked.add('${alert.key}: ${resolved.blocked?.name}');
    }
    _explain(blocked);
    return null;
  }

  /// Say why nothing is on screen, in a build that has the developer surfaces.
  ///
  /// ⚠️ This is not decoration. Four unrelated facts about a machine produce the
  /// identical silence, and each is fixed somewhere else entirely. Whoever is
  /// looking has the figures right there in red and nothing beside them, so the
  /// natural conclusion is that the feature is broken — this is the only thing
  /// that can tell them otherwise.
  void _explain(List<String> blocked) {
    if (!kDebugSurfaceEnabled) return;
    // "No window is near its limit" and "one is, but nothing can be offered"
    // are the two halves of the silence, and they are fixed in completely
    // different places — so they must never print the same line.
    final line = blocked.isEmpty
        ? 'nothing past ${kUsageCriticalPercent.round()}% in '
              '${widget.usage.readings.map(_describe).join(', ')}'
        : blocked.join('; ');
    if (line == _lastSilence) return;
    _lastSilence = line;
    appLog.debug('app', 'usage notice silent — $line');
  }

  /// ⚠️ Called from a post-frame callback, never from `build` itself: this
  /// touches a field and sends an event, and a build that does either is a
  /// build that cannot be run twice.
  void _report(UsageOffer offer) {
    if (!_reported.add(offer.alert.key)) return;
    analytics.usageLimitWarned(
      provider: offer.alert.provider.name,
      window: offer.alert.window.label,
      percent: offer.alert.window.usedPercent.round(),
      action: offer.action.name,
    );
  }

  /// One reading, short enough to sit several to a log line.
  static String _describe(ProviderUsage reading) {
    if (!reading.hasFigures) {
      return '${reading.provider.name}=${reading.status.name}';
    }
    final windows = reading.windows
        .map((w) => '${w.label} ${w.usedPercent.round()}%')
        .join('/');
    return '${reading.provider.name}[$windows]';
  }

  void _dismiss(UsageOffer offer) {
    setState(() => _quietUntil = DateTime.now().add(kUsageNudgeCoolOff));
    analytics.usageLimitDismissed(
      provider: offer.alert.provider.name,
      window: offer.alert.window.label,
    );
    unawaited(_nudges.dismiss(offer.alert.key, offer.alert.dismissedUntil()));
  }

  Future<void> _act(UsageOffer offer) async {
    // ⚠️ Only a MOVE closes this. Moving the agents is a complete answer, and a
    // card still sitting over the panes it just retargeted would be asking a
    // question it had already been given. Choosing a provider is not: it makes
    // the OTHER offer apply, so the card should come back reading "Move 3
    // agents to Water Grid" — which is the step that actually gets the work
    // going again. Silencing it there would strand somebody one click short.
    //
    // Silenced without counting a dismissal, since `usage_limit_offer` already
    // records what happened here.
    if (offer.action == UsageOfferAction.moveAgents) {
      unawaited(_nudges.dismiss(offer.alert.key, offer.alert.dismissedUntil()));
    }
    await runUsageOffer(context, widget.notifier, offer, selection: _selection);
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return ListenableBuilder(
      // The notifier is not here: this card is built inside the shell's own
      // `ListenableBuilder` on it, and listening twice would rebuild it twice
      // for every terminal frame.
      listenable: Listenable.merge([widget.usage, _nudges, _selection]),
      builder: (context, _) {
        final offer = _offer;
        if (offer == null) return const SizedBox.shrink();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _report(offer);
        });
        return UsageLimitCard(
          offer: offer,
          onAct: () => unawaited(_act(offer)),
          onDismiss: () => _dismiss(offer),
        );
      },
    );
  }
}
