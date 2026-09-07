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
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../grid/agent_grid.dart';
import '../grid/grid_agent_override.dart';
import '../grid/grid_models_controller.dart';
import '../grid/grid_selection_store.dart';
import '../grid/node_display.dart' show kAutoModelId, modelKey;
import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/app_menu.dart';
import '../shared/widgets/skeleton.dart';
import '../shared/widgets/toolbar_pill.dart';
import '../state/app_state.dart';

/// The three states an agent can be in, as the header prints them.
String agentModelLabel(AgentGrid? grid) {
  if (grid == null) return 'Own login';
  return grid.model ?? 'Auto';
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

/// The menu's value for "the engine's own login" — distinct from `null`, which means "Auto" (the
/// grid decides). Exported alongside [agentModelMenuOptions] so a caller that reuses the list can
/// recognise this same sentinel rather than invent its own.
const String kOwnLoginModelOption = '__own_login__';

/// One row an agent-model menu can show: a real choice, or — while the grid's models are loading or
/// failed to load — a disabled placeholder that exists to be read, not picked.
class AgentModelOption {
  const AgentModelOption({
    required this.label,
    required this.value,
    this.enabled = true,
  });

  final String label;

  /// `null` = Auto, [kOwnLoginModelOption] = the engine's own login, anything else = a model id.
  /// Meaningless when [enabled] is false.
  final String? value;

  final bool enabled;
}

/// The ordered rows an agent-model menu offers for [state]: own login, auto, then the grid's
/// models — or one disabled note in their place while the list is loading or failed.
///
/// Exported because the New agent dialog's own model picker (a later task) shows this exact same
/// three-part choice when launching a new agent, and must IMPORT this function rather than build a
/// second copy. The option list IS the contract; two copies of it would drift the first time either
/// gained an entry.
List<AgentModelOption> agentModelMenuOptions(GridModelsState state) {
  final options = <AgentModelOption>[
    const AgentModelOption(label: 'Own login', value: kOwnLoginModelOption),
    const AgentModelOption(label: 'Auto', value: null),
  ];
  switch (state) {
    case GridModelsReady(:final models):
      // `auto` is dropped, not listed: the relay advertises its virtual router in `/models` (see
      // [kAutoModelId]), so passing that list through unfiltered put a SECOND "Auto" under the one
      // above — and the two are not the same choice. This one carries `value: null`, which leaves
      // ANTHROPIC_MODEL unset and is the state [agentModelLabel] prints as "Auto"; the relay's row
      // would send `ANTHROPIC_MODEL=auto` and leave the header reading the raw id back. Matching on
      // [modelKey] rather than the string: ids arrive from three sources that disagree on case.
      options.addAll(
        models
            .where((model) => modelKey(model) != kAutoModelId)
            .map((model) => AgentModelOption(label: model, value: model)),
      );
    case GridModelsLoading():
      options.add(
        const AgentModelOption(
          label: 'Loading models…',
          value: '',
          enabled: false,
        ),
      );
    case GridModelsFailed(:final message):
      options.add(AgentModelOption(label: message, value: '', enabled: false));
    case GridModelsIdle():
      break;
  }
  return options;
}

/// The header's per-agent model control. Looks its own value up at build time — see the library doc
/// for why it takes no `grid` parameter.
///
/// Built on [MenuAnchor], not a `PopupMenuButton`: a `PopupMenuButton`'s `itemBuilder` is a
/// one-shot snapshot handed to `showMenu()` before `onOpened` even fires, so a menu opened on a
/// network not yet loaded this session showed only "Own login"/"Auto" until closed and reopened —
/// and right after switching grids could show the PREVIOUS grid's models under the new grid's name,
/// since `gridModelsController` is a single global keyed by one network id. Wrapping the anchor in a
/// `ListenableBuilder` on [gridModelsController] instead means the open panel's rows recompute on
/// every `Idle → Loading → Ready/Failed` step. This control calls `AppNotifier.moveAgentToGrid` for
/// one already-running agent and offers own login as a peer of Auto and every model — built on the
/// app's own row primitives ([AppMenuItem], [AppMenuDivider]) rather than a bespoke shape.
class AgentModelMenu extends StatefulWidget {
  const AgentModelMenu({
    super.key,
    required this.notifier,
    required this.machineId,
    required this.agentId,
    required this.engine,
  });

  final AppNotifier notifier;
  final String machineId;
  final String agentId;
  final String engine;

  @override
  State<AgentModelMenu> createState() => AgentModelMenuState();
}

/// Public only for [debugSetPending] — a widget test cannot reach a private State to put this
/// control in flight, and driving it there for real means an HTTP round trip.
class AgentModelMenuState extends State<AgentModelMenu> {
  final _controller = MenuController();

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

  // Drawn as hovered while the panel hangs off it, so the control does not go quiet under its own
  // open menu — [MenuAnchor] gives no state for this, and without it the pill loses its fill the
  // moment the pointer moves off the button and onto the list it just opened.
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return ValueListenableBuilder<GridSelection>(
      valueListenable: gridSelectionStore,
      builder: (context, selection, _) {
        final capable = kGridCapableEngines.contains(widget.engine);
        // Listens to the NOTIFIER, not just the models controller: `busy` below is turn state, and
        // nothing else in this subtree rebuilds when a turn starts or ends (the pane header holds no
        // listener of its own). Without this the pill would latch at whatever it was built with and
        // stay disabled after the turn it was disabled for had finished.
        return ListenableBuilder(
          listenable: widget.notifier,
          builder: (context, _) {
            // Qualified by the two standing conditions, not raw turn state: `busy` is what earns
            // the hourglass and the sentence that promises the control comes back, and neither is
            // true of an agent that is also mid-turn on an engine with no grid to move to. Those
            // do not clear when the turn ends, so they are named first and this stays false.
            final busy =
                capable &&
                selection.hasGrid &&
                widget.notifier.agentIsProcessing(
                  widget.machineId,
                  widget.agentId,
                );
            final enabled = capable && selection.hasGrid && !_pending && !busy;
            // Ordered by what the user can do about it: the two standing conditions first, then
            // the one that clears on its own. Busy sits last because it outranks nothing — an
            // engine that cannot use a grid says so whether or not it is mid-turn.
            final tooltip = !capable
                ? '${widget.engine} cannot use a grid'
                : !selection.hasGrid
                ? 'Pick a grid to change this agent\'s model'
                : busy
                ? 'Agent is running a turn — changing the model would restart it '
                      'and lose the turn. This unlocks when the turn finishes.'
                : 'Changing the model restarts the agent';
            return _buildPill(
              context,
              selection: selection,
              capable: capable,
              enabled: enabled,
              busy: busy,
              tooltip: tooltip,
            );
          },
        );
      },
    );
  }

  /// The pill itself, split out only so [build] stays readable through three nested builders.
  Widget _buildPill(
    BuildContext context, {
    required GridSelection selection,
    required bool capable,
    required bool enabled,
    required bool busy,
    required String tooltip,
  }) {
    // See the class doc: this is what keeps an ALREADY-OPEN menu's rows current as
    // gridModelsController moves through its states, rather than freezing them at open time.
    return ListenableBuilder(
      listenable: gridModelsController,
      builder: (context, _) {
        final currentGrid = agentGridOf(
          widget.notifier,
          widget.machineId,
          widget.agentId,
        );
        final label = agentModelLabel(currentGrid);
        final currentValue = currentGrid == null
            ? kOwnLoginModelOption
            : currentGrid.model;
        return Tooltip(
          message: tooltip,
          child: MenuAnchor(
            controller: _controller,
            // Bounded because the note at the top of this list is a
            // sentence. Left to the theme's default the panel is unbounded,
            // and the sentence is clipped rather than wrapped — see
            // [AppMenuNote.panelWidth].
            style: grid.AppMenu.style(maxWidth: _panelMaxWidth),
            onOpen: () {
              setState(() => _open = true);
              final networkId = selection.networkId;
              if (networkId != null) {
                gridModelsController.ensureLoadedFor(networkId);
              }
            },
            onClose: () {
              // Guarded: the menu closes on route teardown too, after this State is gone.
              if (mounted) setState(() => _open = false);
            },
            menuChildren: _rows(currentValue),
            builder: (context, controller, _) => ToolbarPill(
              active: _open,
              // Rimmed whenever this engine could use the menu at all — including mid-restart,
              // when `enabled` is briefly false because a second tap must not land. The pill
              // sits alone among plain labels in the pane header, so at rest it needs the rim
              // to read as pressable; dropping it for the moment the model is changing would
              // blink the one box on the strip. A rim on an engine that can NEVER open the
              // menu would draw a box around something inert, so that case keeps none.
              rimmed: capable && selection.hasGrid,
              // Only for busy. The other two disabled states drop the rim as well, so there is
              // nothing left that claims to be pressable and `basic` is already honest; a mid-turn
              // pill keeps its rim and its ink, and the pointer is what says the refusal is real.
              disabledCursor: busy ? SystemMouseCursors.forbidden : null,
              onTap: enabled
                  ? () => controller.isOpen
                        ? controller.close()
                        : controller.open()
                  : null,
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
                        SkeletonText(
                          style: grid.AppFont.codeStyle(),
                          // Held at the label's own width so the strip does not resize under
                          // the pointer mid-restart, and the rim stays where it was.
                          width: _labelWidth(context, label),
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
                        // Leads the label rather than trailing it: this says the AGENT is working,
                        // which is a fact about the pane the pill sits in, while the chevron on the
                        // other end is about the menu. Putting both on the right made one slot mean
                        // two different things. Same indicator the rail draws in its badge slot for
                        // the same agent (`machine_rail.dart`) — one turn, one glyph, two places.
                        if (busy) ...[
                          SizedBox(
                            width: grid.AppControl.iconSizeChip - 2,
                            height: grid.AppControl.iconSizeChip - 2,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.6,
                              color: grid.AppPalette.online,
                            ),
                          ),
                          const SizedBox(width: 5),
                        ],
                        // Flexible, not bare: the pill hugs its label, but a long grid model id
                        // in a narrow pane has to ellipsize inside it rather than overflow it.
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: grid.AppFont.codeStyle(
                              color: ToolbarPill.tint(
                                tinted: false,
                                enabled: enabled,
                              ),
                            ),
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
          ),
        );
      },
    );
  }

  /// The width the label is currently drawn at, so the skeleton standing in for it holds the
  /// pill's size steady.
  ///
  /// Measured rather than guessed: the model id is whatever the grid serves, the mono face is the
  /// user's own (Settings ▸ Terminal), and a placeholder that does not match is the jump a skeleton
  /// exists to prevent. Deliberately uncapped — the header already bounds this control, and a cap
  /// here made the pill shrink the moment a restart began and spring back when it ended.
  double _labelWidth(BuildContext context, String label) {
    // Measured exactly the way SkeletonText measures its own line: the ambient DefaultTextStyle
    // merged in first, then the context's scaler. Skipping the merge is a few pixels out, which is
    // enough to see the pill twitch as the placeholder swaps in.
    final resolved = DefaultTextStyle.of(context).style
        .merge(grid.AppFont.codeStyle());
    final painter = TextPainter(
      text: TextSpan(text: label, style: resolved),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// The panel's width, stated once — read by [AppMenu.style] and by the note
  /// that has to wrap inside it. Wider than the grid picker's: this list holds
  /// model ids, which are longer than a grid's name.
  static const double _panelMaxWidth = 320;

  /// The panel's rows: a standing note that picking restarts the agent, then
  /// [agentModelMenuOptions] turned into entries — a real, tappable [AppMenuItem] for each choice,
  /// and a plain [AppMenuNote] in their place for the loading/failed placeholder, which exists to
  /// be read rather than picked.
  List<Widget> _rows(String? currentValue) {
    return [
      const AppMenuNote(
        'Changing the model restarts this agent and resumes the conversation',
        panelWidth: _panelMaxWidth,
      ),
      const AppMenuDivider(),
      for (final option in agentModelMenuOptions(gridModelsController.state))
        if (option.enabled)
          AppMenuItem(
            label: option.label,
            selected: option.value == currentValue,
            onPressed: () {
              _controller.close();
              unawaited(_apply(option.value));
            },
          )
        else
          AppMenuNote(option.label),
    ];
  }

  Future<void> _apply(String? value) async {
    if (_pending) return;
    setState(() => _pending = true);

    GridAgentOverride? override;
    if (value != kOwnLoginModelOption) {
      try {
        override = await resolveGridAgentOverride(model: value);
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
    if (!mounted) return;
    setState(() => _pending = false);
    if (message != null && message != AppNotifier.agentVanished) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
