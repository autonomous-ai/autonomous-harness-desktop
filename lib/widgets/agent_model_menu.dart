/// What an agent's model is, and how to change it.
///
/// ⚠️ This control holds NO state of its own. The model an agent is running is `agent.grid`, which
/// the CLI reads off the live process every discovery pass — a process's environment is fixed at
/// exec, so that is the only thing that actually decides where its requests go. Two bugs on
/// 2026-09-04 were client-side copies of exactly this field drifting from it; a third copy here
/// would be the same bug with a nicer name.
///
/// Changing the model RESTARTS the agent. That is not a choice: the environment cannot be changed
/// under a running process. The restart is cheap (`--resume`, same pane, same scrollback) and the
/// CLI refuses the one expensive case itself, answering AGENT_BUSY mid-turn rather than losing work —
/// which is why picking applies immediately instead of opening a confirmation nobody needs.
///
/// That refusal is the CLI's floor, not this control's behaviour. The app already knows which agents
/// are mid-turn — `MachineState.processingAgentIds`, fed by `turn_started`/`turn_ended` — so the
/// control disables itself for exactly the agents the CLI would refuse, and says why on hover. The
/// AGENT_BUSY path stays as the backstop it always was: the turn can start in the gap between a
/// build and a tap, and only the CLI reads the pane itself.
///
/// The list of choices is no longer here. It is a dialog — `widgets/model_picker_dialog.dart` —
/// grouped by provider, because an account is on several and a menu that could only offer the
/// models of the sidebar's default made "run this agent on that other provider" a trip through
/// Settings that also changed where every FUTURE agent launched. This file keeps what the pill
/// owes the reader (the model, and why it will not open) and what applying a pick costs (a mint, a
/// retarget, a refusal worth naming).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../grid/agent_grid.dart';
import '../grid/grid_agent_override.dart';
import '../grid/grid_network.dart';
import '../grid/grid_networks_controller.dart';
import '../grid/grid_selection_store.dart';
import '../grid/grid_surface.dart';
import '../grid/model_picker_options.dart';
import '../grid/node_display.dart' show withoutGridRunPrefix;
import '../grid/model_recents_store.dart';
import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/skeleton.dart';
import '../shared/widgets/toolbar_pill.dart';
import '../state/app_state.dart';
import 'model_picker_dialog.dart';

/// What the pill PRINTS — one word, always the same one.
///
/// It used to print the model id itself, which is the answer a reader wants but
/// not one this strip has room for: a pane header already carries the agent's
/// name, a status dot, a transport badge and the pane's own buttons, and four
/// panes side by side leave the pill about 150px. A real id ("DeepSeek-V4-Flash
/// -0731") ellipsized to "DeepSeek-V4-F…" in every tile that mattered, which
/// answers nothing and costs the width anyway. The name of the SETTING fits
/// whatever the answer is; the answer itself is in the tooltip, and in the
/// picker, where the row the agent is on is ticked.
const String kModelPillLabel = 'Model';

/// The three states an agent can be in, as the header names them on hover.
///
/// The same three [ModelChoice.label] prints in the picker, and deliberately the
/// same words and the same stripping — the header names the row the picker
/// ticks, and a grid-run prefix shown in one place and hidden in the other reads
/// as two different models. It cannot BE that method: what the CLI reports for a
/// running agent is a relay URL and a model, with no provider name in it.
String agentModelLabel(AgentGrid? grid) {
  if (grid == null) return kNoGridTargetLabel;
  final model = grid.model;
  return model == null ? kAutoModelLabel : withoutGridRunPrefix(model);
}

/// This agent's grid, read from the notifier at the moment of asking.
///
/// A plain loop rather than `firstWhereOrNull`: `package:collection` is not a dependency of this
/// project, and adding one for a three-line lookup is not a trade worth making.
AgentGrid? agentGridOf(AppNotifier notifier, String machineId, String agentId) {
  final agents = notifier.stateOf(machineId)?.agents ?? const <Agent>[];
  for (final agent in agents) {
    if (agent.id == agentId) return agent.grid;
  }
  return null;
}

/// The providers the account is on, or none while it is still being asked.
///
/// Deliberately NOT filtered by `providerEnablementStore`: this list exists to
/// NAME the provider an agent is already running on, and an agent does not
/// leave a grid because the switch for it was turned off here.
List<GridNetwork> accountProviders([GridNetworksController? controller]) {
  final state = (controller ?? gridNetworksController).state;
  return state is GridNetworksReady ? state.me.networks : const [];
}

/// The header's per-agent model control. Looks its own value up at build time — see the library doc
/// for why it takes no `grid` parameter.
///
/// The pill opens [showModelPickerDialog] and applies whatever it returns. It offers "No provider"
/// as a peer of Auto and every model, on every provider this computer will offer — so one pick can
/// move an agent to another provider AND pin a model on it, which is one restart rather than two.
class AgentModelMenu extends StatefulWidget {
  const AgentModelMenu({
    super.key,
    required this.notifier,
    required this.machineId,
    required this.agentId,
    required this.engine,
    @visibleForTesting this.gridSurface = kGridSurfaceEnabled,
  });

  final AppNotifier notifier;
  final String machineId;
  final String agentId;
  final String engine;

  /// Whether this build has providers at all.
  ///
  /// A compile-time const in the app, which makes the shipped build's own
  /// behaviour — no pill, because there is no feature behind it — unreachable
  /// from a test run, where it is always true. Passed in so that case can be
  /// asserted, exactly as `GridSelectionStore` takes it.
  final bool gridSurface;

  @override
  State<AgentModelMenu> createState() => AgentModelMenuState();
}

/// Public only for [debugSetPending] — a widget test cannot reach a private State to put this
/// control in flight, and driving it there for real means an HTTP round trip.
class AgentModelMenuState extends State<AgentModelMenu> {
  // True while a pick is in flight, so a second tap cannot fire a second restart on top of the
  // first one before the CLI has answered.
  bool _pending = false;

  /// Puts the control into its in-flight state without a network round trip.
  ///
  /// Picking for real goes through `resolveGridAgentOverride`, which mints a relay key over HTTP —
  /// a widget test that drove the menu would be asserting against Dio's timers rather than against
  /// what the header draws. This is the same seam the app's other widgets expose for exactly this
  /// (see `AppNotifier.handleEventForTest`).
  @visibleForTesting
  void debugSetPending(bool value) => setState(() => _pending = value);

  // Drawn as hovered while the picker is open, so the control does not go quiet under its own
  // dialog — the pointer leaves the pill the moment the panel appears.
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    // The only reason this control is ever absent: a build with no providers in
    // it at all. It used to leave whenever the SIDEBAR had no default provider,
    // which was right while the menu could only offer that one grid's models —
    // with none picked there was nothing behind the pill. The picker now lists
    // every provider this computer offers and can say, in its own words, that
    // there are none yet or that Grid needs signing into, so hiding the door to
    // it left an agent's model unreadable and unchangeable for exactly the
    // people who had not found the sidebar's picker.
    if (!widget.gridSurface) return const SizedBox.shrink();
    final capable = kGridCapableEngines.contains(widget.engine);
    // Listens to the NOTIFIER: `busy` below is turn state, and nothing else in this subtree
    // rebuilds when a turn starts or ends (the pane header holds no listener of its own). Without
    // this the pill would latch at whatever it was built with and stay disabled after the turn it
    // was disabled for had finished. It is also what repaints the label when the CLI's next
    // discovery pass reports the agent on its new model.
    return ListenableBuilder(
      listenable: widget.notifier,
      builder: (context, _) {
        // Qualified by the standing condition, not raw turn state: `busy` is what earns the
        // forbidden cursor and the sentence that promises the control comes back, and neither
        // is true of an agent that is also mid-turn on an engine with no grid to move to. That
        // one does not clear when the turn ends, so it is named first and this stays false.
        final busy =
            capable &&
            widget.notifier.agentIsProcessing(widget.machineId, widget.agentId);
        final enabled = capable && !_pending && !busy;
        // Ordered by what the user can do about it: the standing condition first, then the one
        // that clears on its own. Busy sits last because it outranks nothing — an engine that
        // cannot use a grid says so whether or not it is mid-turn.
        // The model the pill no longer has room to print. It leads every
        // sentence below because it is the thing a reader hovers to find out —
        // the caveat after it is what happens if they act on it.
        final current = agentModelLabel(
          agentGridOf(widget.notifier, widget.machineId, widget.agentId),
        );
        final tooltip = !capable
            ? '$current · ${widget.engine} cannot use a grid'
            : busy
            ? '$current · the agent is running a turn — changing the model '
                  'would restart it and lose the turn. This unlocks when the '
                  'turn finishes.'
            : '$current · changing the model restarts the agent';
        return _buildPill(
          context,
          capable: capable,
          enabled: enabled,
          busy: busy,
          tooltip: tooltip,
        );
      },
    );
  }

  /// The pill itself, split out only so [build] stays readable through two nested builders.
  Widget _buildPill(
    BuildContext context, {
    required bool capable,
    required bool enabled,
    required bool busy,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: ToolbarPill(
        active: _open,
        // Rimmed whenever this engine could use the picker at all — including mid-restart,
        // when `enabled` is briefly false because a second tap must not land. The pill
        // sits alone among plain labels in the pane header, so at rest it needs the rim
        // to read as pressable; dropping it for the moment the model is changing would
        // blink the one box on the strip. A rim on an engine that can NEVER open the
        // picker would draw a box around something inert, so that case keeps none.
        rimmed: capable,
        // Only for busy. The other disabled state — an engine that can never use a grid —
        // drops the rim as well, so nothing there claims to be pressable and `basic` is
        // already honest; a mid-turn
        // pill keeps its rim and its ink, and the pointer is what says the refusal is real.
        disabledCursor: busy ? SystemMouseCursors.forbidden : null,
        onTap: enabled ? () => unawaited(_pick(context)) : null,
        child: _pending
            // A skeleton, not a spinner: the shape is already known — the same one line
            // of mono type, about to say a different model — so the pill keeps its
            // metrics and nothing jumps when the answer lands. (The spinner here was
            // also drawn 12x24: ToolbarPill's box is a fixed 26px tall, which hands its
            // single child a tight height, and a bare SizedBox took it instead of
            // shrinking — a Row escapes that with mainAxisSize.min, a SizedBox cannot.)
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Flexible for the same reason the word below is: a measured
                  // width has no ellipsis to fall back on, so in a pane narrower
                  // than it the skeleton would strike the header with an
                  // overflow stripe for the length of the restart. Bounded, the
                  // SizedBox inside clamps to what is there.
                  Flexible(
                    child: SkeletonText(
                      style: _labelStyle(enabled: false),
                      // Held at the word's own width so the strip does not resize under
                      // the pointer mid-restart, and the rim stays where it was.
                      width: _labelWidth(context),
                    ),
                  ),
                  // The chevron's slot, kept empty rather than collapsed: it is dropped
                  // while `enabled` is false, and letting the pill lose that width for
                  // the length of a restart is the same jump the skeleton prevents.
                  const SizedBox(width: 4 + grid.AppControl.iconSizeChip),
                ],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // NO turn indicator here, deliberately. A spinner in this slot said "the
                  // agent is working"; the skeleton a few lines up says "the model you picked
                  // is being applied" — two meanings, one control, both drawn as motion, and
                  // they were read as the same thing. The one that belongs to this pill is
                  // the one about this pill, so the other left.
                  //
                  // Nothing is lost. The turn is already on screen twice over: the pane this
                  // header sits on is the turn, running, in full; and the rail draws the
                  // spinner beside the agent's row (`machine_rail.dart`), where it earns its
                  // place because the pane may not be open. What the pill owes the reader is
                  // why it will not open — and that is carried by the dimmed label, the
                  // forbidden cursor and the tooltip, which say it in words.
                  // Flexible, not bare: one word fits any pane worth working in,
                  // but the header is laid out from the right and a tile can
                  // always be dragged narrower than the word.
                  Flexible(
                    child: Text(
                      kModelPillLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _labelStyle(enabled: enabled),
                    ),
                  ),
                  // The affordance the control was missing: this restarts the agent, and
                  // a bare label gave no sign it could be pressed at all. Dropped when
                  // disabled — there is nothing to open, so a chevron would lie.
                  if (enabled) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.expand_more_rounded,
                      size: grid.AppControl.iconSizeChip,
                      color: grid.AppPalette.textFaint,
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  /// The word's ink: the UI face, not the terminal's.
  ///
  /// It was the mono face while the pill printed a model id, which belongs in
  /// mono — this is a control's LABEL now, and the app sets those in its own
  /// sans, like every other pill in a toolbar.
  TextStyle _labelStyle({required bool enabled}) => TextStyle(
    fontFamily: grid.AppFont.sans,
    fontFamilyFallback: grid.AppFont.sansFallback,
    fontSize: 12.5,
    fontWeight: grid.AppFont.medium,
    color: ToolbarPill.tint(tinted: false, enabled: enabled),
  );

  /// The width the word is drawn at, so the skeleton standing in for it holds
  /// the pill's size steady.
  ///
  /// Measured rather than guessed: the UI face and its scale are the user's own
  /// (Settings ▸ Appearance), and a placeholder that does not match is the jump
  /// a skeleton exists to prevent.
  double _labelWidth(BuildContext context) {
    // Measured exactly the way SkeletonText measures its own line: the ambient DefaultTextStyle
    // merged in first, then the context's scaler. Skipping the merge is a few pixels out, which is
    // enough to see the pill twitch as the placeholder swaps in.
    final resolved = DefaultTextStyle.of(context).style
        .merge(_labelStyle(enabled: false));
    final painter = TextPainter(
      text: TextSpan(text: kModelPillLabel, style: resolved),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// Open the picker, and apply what it hands back.
  Future<void> _pick(BuildContext context) async {
    setState(() => _open = true);
    final current = currentModelChoice(
      agentGridOf(widget.notifier, widget.machineId, widget.agentId),
      accountProviders(),
    );
    final choice = await showModelPickerDialog(context, current: current);
    // Guarded: the pane can close under an open dialog — a machine going
    // offline takes its panes with it.
    if (!mounted) return;
    setState(() => _open = false);
    // Dismissed, or the row the agent is already on. Neither is worth a restart:
    // re-applying the model it is running would cost the turn's scrollback for
    // nothing.
    if (choice == null || choice == current) return;
    await _apply(choice);
  }

  Future<void> _apply(ModelChoice choice) async {
    if (_pending) return;
    setState(() => _pending = true);

    GridAgentOverride? override;
    if (choice.hasProvider) {
      try {
        // The picker's provider, not the sidebar's: a pick can move the agent
        // to a grid this computer does not launch NEW agents against, and the
        // default is not touched by moving one agent.
        override = await resolveGridAgentOverride(
          selection: GridSelection(
            networkId: choice.networkId,
            networkName: choice.networkName,
          ),
          model: choice.model,
        );
      } catch (error) {
        if (!mounted) return;
        setState(() => _pending = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
        return;
      }
    }

    final message = await widget.notifier.moveAgentToGrid(
      widget.machineId,
      widget.agentId,
      override,
    );
    // Remembered only once the CLI has actually moved the agent: a Recent list
    // that filled up with refusals would offer, at the top, exactly the picks
    // that did not work.
    if (message == null) unawaited(modelRecentsStore.remember(choice));
    if (!mounted) return;
    setState(() => _pending = false);
    if (message != null && message != AppNotifier.agentVanished) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
