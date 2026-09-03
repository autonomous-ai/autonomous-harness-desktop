import 'package:flutter/material.dart';

import '../grid/grid_retarget.dart';
import '../grid/grid_selection_store.dart';
import '../shared/theme/app_theme.dart' as grid;
import '../state/app_state.dart';

/// How long the card takes to arrive, and to go.
///
/// The app's 220 and 160, named here for what they do rather than reached for
/// as `fold` and `swap`: this is a toast, not a panel folding.
const Duration _enter = grid.AppMotion.fold;
const Duration _leave = grid.AppMotion.swap;

/// "2 agents are still on their old target — move them?"
///
/// Picking a grid retargets new agents by itself; a running one has to be restarted, because a
/// process's environment cannot be changed under it. That restart is the user's call, so this states
/// what is out of date and waits. It never moves anything on its own.
///
/// Dismissal is keyed on the selection, so closing it is quiet about THIS choice and a later change
/// of grid asks again — which is the moment the question is live once more.
///
/// Shaped like Grid's own toast (`autonomous-grid-app/lib/shared/widgets/toast.dart`): a floating
/// card at top-centre, not a strip welded to the window edge. That is not only nicer — the edge is
/// where the traffic lights and the error strip already live, and a banner there had to dodge both.
class GridRetargetBanner extends StatefulWidget {
  const GridRetargetBanner({super.key, required this.notifier});

  final AppNotifier notifier;

  @override
  State<GridRetargetBanner> createState() => _GridRetargetBannerState();
}

class _GridRetargetBannerState extends State<GridRetargetBanner> {
  GridSelection? _dismissed;
  bool _moving = false;
  List<RetargetOutcome>? _report;

  Future<void> _moveAll(List<StaleAgent> stale, GridSelection selection) async {
    setState(() {
      _moving = true;
      _report = null;
    });
    final outcomes = await retargetAgents(
      notifier: widget.notifier,
      stale: stale,
      selection: selection,
    );
    if (!mounted) return;
    setState(() {
      _moving = false;
      // Kept on screen only while something did NOT move: a clean sweep needs no receipt, and the
      // agents themselves are the evidence.
      _report = outcomes.any((outcome) => !outcome.moved) ? outcomes : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return ValueListenableBuilder<GridSelection>(
      valueListenable: gridSelectionStore,
      builder: (context, selection, _) {
        final card = _cardFor(selection);
        return Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Align(
            alignment: Alignment.topCenter,
            // Declarative rather than a controller driven from `build`: what is on screen is a pure
            // function of the selection and the report, so the animation should be too.
            child: AnimatedSwitcher(
              // Enter is the longer half. The card drops in from above and has
              // to be caught; leaving is a decision the user already made, and
              // waiting on the old one is what makes a switcher feel sluggish.
              duration: _enter,
              reverseDuration: _leave,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => SlideTransition(
                position: Tween(
                  begin: const Offset(0, -0.35),
                  end: Offset.zero,
                ).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: card ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }

  Widget? _cardFor(GridSelection selection) {
    final report = _report;
    if (report != null) {
      return _Card(
        // Keyed by which card this is, and it is load-bearing: both branches
        // build a `_Card`, so without a key `AnimatedSwitcher` reads the
        // receipt replacing the offer as the SAME widget being updated and
        // cuts straight between them — exactly as if there were no switcher.
        key: const ValueKey('report'),
        icon: Icons.warning_amber_rounded,
        tone: grid.AppPalette.warn,
        message: _reportMessage(report),
        onDismiss: () => setState(() => _report = null),
      );
    }
    if (!selection.hasGrid || selection == _dismissed) return null;
    final stale = agentsNeedingRetarget(widget.notifier, selection);
    if (stale.isEmpty) return null;
    final one = stale.length == 1;
    return _Card(
      key: const ValueKey('retarget'),
      icon: Icons.bolt_rounded,
      tone: grid.AppPalette.accentOnSurface,
      message:
          '${stale.length} running ${one ? 'agent is' : 'agents are'} on an older target. '
          'Moving ${one ? 'it' : 'them'} to ${selection.label} restarts '
          '${one ? 'it' : 'them'} and resumes the conversation.',
      actionLabel: 'Move',
      busy: _moving,
      onAction: () => _moveAll(stale, selection),
      onDismiss: () => setState(() => _dismissed = selection),
    );
  }

  /// Names what did not move, because that is the part the user still has to do something about.
  static String _reportMessage(List<RetargetOutcome> outcomes) {
    final moved = outcomes.where((outcome) => outcome.moved).length;
    final failed = outcomes.where((outcome) => !outcome.moved);
    final head = moved == 0 ? 'Nothing moved' : 'Moved $moved';
    return '$head · ${failed.map((f) => '${f.name} — ${f.error}').join(' · ')}';
  }
}

/// The card itself — Grid's toast shape, with one action and a close.
class _Card extends StatelessWidget {
  const _Card({
    super.key,
    required this.icon,
    required this.tone,
    required this.message,
    required this.onDismiss,
    this.actionLabel,
    this.onAction,
    this.busy = false,
  });

  final IconData icon;
  final Color tone;
  final String message;
  final VoidCallback onDismiss;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: grid.AppGlass.surfaceFill,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: grid.AppPalette.divider),
            boxShadow: grid.AppGlass.shadow,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ToneIcon(icon: icon, color: tone),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: grid.AppPalette.textPrimary,
                      fontSize: 13,
                      height: 1.35,
                      fontWeight: grid.AppFont.semibold,
                    ),
                  ),
                ),
                if (busy) ...[
                  const SizedBox(width: 12),
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 6),
                ] else if (actionLabel != null) ...[
                  const SizedBox(width: 10),
                  TextButton(
                    key: const Key('grid-retarget-action'),
                    // Compact: this is a thin strip, not a page.
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, grid.AppControl.heightSmall),
                      padding: grid.AppControl.paddingSmall,
                    ),
                    onPressed: onAction,
                    child: Text(actionLabel!),
                  ),
                ],
                const SizedBox(width: 2),
                IconButton(
                  key: const Key('grid-retarget-dismiss'),
                  tooltip: 'Dismiss',
                  onPressed: onDismiss,
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  color: grid.AppPalette.textFaint,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToneIcon extends StatelessWidget {
  const _ToneIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 16, color: color),
    );
  }
}
