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
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../grid/agent_grid.dart';
import '../grid/grid_agent_override.dart';
import '../grid/grid_models_controller.dart';
import '../grid/grid_selection_store.dart';
import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/app_menu.dart';
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
      options.addAll(
        models.map((model) => AgentModelOption(label: model, value: model)),
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
/// every `Idle → Loading → Ready/Failed` step — the same fix `ModelMenu` in
/// `grid_selector_menus.dart` already applies for the sidebar's own model picker. That widget itself
/// was not reusable here: it writes a pick straight to `gridSelectionStore` and has no "Own login"
/// row (that choice lives on `GridMenu`, a NETWORK picker, one level up) — this control instead
/// calls `AppNotifier.moveAgentToGrid` for one already-running agent and offers own login as a peer
/// of Auto and every model. Reusing its rows ([AppMenuItem], [AppMenuDivider]) rather than its
/// `ModelMenu` class keeps the same look without forcing an unrelated callback shape onto it.
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
  State<AgentModelMenu> createState() => _AgentModelMenuState();
}

class _AgentModelMenuState extends State<AgentModelMenu> {
  final _controller = MenuController();

  // True while a pick is in flight, so a second tap cannot fire a second restart on top of the
  // first one before the CLI has answered.
  bool _pending = false;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return ValueListenableBuilder<GridSelection>(
      valueListenable: gridSelectionStore,
      builder: (context, selection, _) {
        final capable = kGridCapableEngines.contains(widget.engine);
        final enabled = capable && selection.hasGrid && !_pending;
        final tooltip = !capable
            ? '${widget.engine} cannot use a grid'
            : !selection.hasGrid
            ? 'Pick a grid to change this agent\'s model'
            : 'Changing the model restarts the agent';
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
                onOpen: () {
                  final networkId = selection.networkId;
                  if (networkId != null) {
                    gridModelsController.ensureLoadedFor(networkId);
                  }
                },
                menuChildren: _rows(currentValue),
                builder: (context, controller, _) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: enabled
                      ? () => controller.isOpen ? controller.close() : controller.open()
                      : null,
                  child: Opacity(
                    opacity: enabled ? 1 : 0.55,
                    child: _pending
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 1.6),
                          )
                        : Text(
                            label,
                            style: grid.AppFont.codeStyle(color: grid.AppPalette.textFaint),
                          ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// The panel's rows: a standing note that picking restarts the agent, then
  /// [agentModelMenuOptions] turned into entries — a real, tappable [AppMenuItem] for each choice,
  /// and a plain [_MenuNoteRow] in their place for the loading/failed placeholder, which exists to
  /// be read rather than picked.
  List<Widget> _rows(String? currentValue) {
    return [
      const _MenuNoteRow('Changing the model restarts the agent'),
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
          _MenuNoteRow(option.label),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

/// A non-interactive row, laid out on the same column an [AppMenuItem]'s label starts on (its icon
/// slot, empty, plus the gap that follows it) so it reads as part of the same list rather than an
/// aside bolted onto it. Used for the standing "this restarts the agent" note and for the
/// loading/failed placeholder [agentModelMenuOptions] returns in place of a pick.
class _MenuNoteRow extends StatelessWidget {
  const _MenuNoteRow(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    const metrics = AppMenuRowMetrics.compact;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Padding(
        padding: metrics.padding,
        child: Row(
          children: [
            SizedBox(width: metrics.iconSize),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: grid.AppPalette.textFaint,
                  fontFamily: grid.AppFont.sans,
                  fontFamilyFallback: grid.AppFont.sansFallback,
                  fontSize: metrics.noteSize,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
