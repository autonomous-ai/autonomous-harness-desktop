/// Pick a model — on any provider this computer offers.
///
/// A dialog rather than the dropdown it replaces, and the shape is OpenCode's
/// model picker: a search field, then one group per PROVIDER with the models it
/// serves under it, and the last few picks at the top. The dropdown could only
/// list the models of the provider the sidebar had picked, so moving an agent
/// onto a model somewhere else meant a trip to the sidebar to change the
/// default for every future agent, then back to the header — and the default
/// stayed changed.
///
/// What it does NOT do is decide anything: it returns a [ModelChoice] and the
/// caller applies it (`widgets/agent_model_menu.dart`), which is what keeps the
/// restart, its refusals and the recents in one place instead of two. What the
/// panel LOOKS like is `model_picker_chrome.dart`; what is in the list is
/// `grid/model_picker_options.dart`. This file is the behaviour between them.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../grid/grid_models_controller.dart';
import '../grid/grid_network.dart';
import '../grid/grid_networks_controller.dart';
import '../grid/model_picker_options.dart';
import '../grid/model_recents_store.dart';
import '../grid/provider_enablement_store.dart';
import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/app_menu.dart';
import '../shared/widgets/empty_state.dart';
import 'model_picker_chrome.dart';

/// Opens the picker, resolving to the chosen model or to null when it was
/// dismissed.
///
/// [current] is where the agent is running now — ticked in the list, and where
/// the highlight starts. Null is a real value: an agent can be on a provider
/// this account cannot name (see [currentModelChoice]), and nothing is then
/// ticked rather than something being ticked wrongly.
Future<ModelChoice?> showModelPickerDialog(
  BuildContext context, {
  required ModelChoice? current,
}) => showDialog<ModelChoice>(
  context: context,
  builder: (_) => ModelPickerDialog(current: current),
);

/// Public for its widget test, which drives the keyboard through it — the panel
/// is the feature, and it is unreachable from the pill without a live account.
class ModelPickerDialog extends StatefulWidget {
  const ModelPickerDialog({
    super.key,
    required this.current,
    this.networks,
    this.models,
    this.recents,
    this.enablement,
  });

  final ModelChoice? current;

  /// The four sources this panel reads, injectable ONLY so a test can stand
  /// them up without a Grid session. The app passes none of them and gets the
  /// shared singletons — a second copy of any of these is a second answer to
  /// "which providers are there", which is the drift they are singletons to
  /// avoid.
  final GridNetworksController? networks;
  final GridModelsController? models;
  final ModelRecentsStore? recents;
  final ProviderEnablementStore? enablement;

  @override
  State<ModelPickerDialog> createState() => _ModelPickerDialogState();
}

class _ModelPickerDialogState extends State<ModelPickerDialog> {
  final _query = TextEditingController();
  final _scroll = ScrollController();
  late final FocusNode _field = FocusNode(onKeyEvent: _onKey);

  /// What Enter would pick — the CHOICE, not its row number.
  ///
  /// A provider answering late inserts its models into the middle of the list,
  /// and an index held across that rebuild would silently come to mean a
  /// different row: the highlight would appear to jump while nobody touched the
  /// keyboard. A choice survives the list moving under it, and simply stops
  /// being found when a search takes it away — which is exactly when nothing
  /// should be highlighted.
  ModelChoice? _highlight;

  /// The list the last build drew, kept so the keyboard handler and the scroll
  /// arithmetic act on exactly what is on screen rather than on a list rebuilt
  /// from stores that may have moved since.
  List<ModelPickerItem> _items = const [];

  /// Whether the reader has taken the keyboard — a move, or a keystroke in the
  /// search field.
  ///
  /// Until they have, the panel keeps trying to put the highlight on the row the
  /// agent is actually running: that row does not exist on the frame the panel
  /// opens on, because its provider's models are still a round trip away, and a
  /// highlight placed once on the first build would leave the panel opening on
  /// the subscription row every time. After they have, it is theirs — a late-arriving
  /// provider must not yank the highlight out from under an arrow key.
  bool _touched = false;

  GridNetworksController get _networks =>
      widget.networks ?? gridNetworksController;
  GridModelsController get _models => widget.models ?? gridModelsController;
  ModelRecentsStore get _recents => widget.recents ?? modelRecentsStore;
  ProviderEnablementStore get _enablement =>
      widget.enablement ?? providerEnablementStore;

  /// The four sources, merged ONCE.
  ///
  /// `Listenable.merge` builds a new object every time it is called, and a
  /// `ListenableBuilder` handed a fresh one on every build tears down and
  /// re-registers four listeners per frame. Held here, the panel subscribes
  /// once and the rebuilds are the notifications rather than the plumbing.
  late final Listenable _sources = Listenable.merge([
    _networks,
    _models,
    _recents,
    _enablement,
  ]);

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    // Asked for on every build rather than in initState: both are idempotent
    // (`ensureLoaded` fetches only from Idle), and the models of a provider
    // that arrives late have to be asked for on the build that first sees it —
    // initState runs before the account's own list has landed.
    _networks.ensureLoaded();
    return ListenableBuilder(
      listenable: _sources,
      builder: (context, _) {
        final providers = _providers();
        _models.ensureLoadedForAll(
          providers.map((provider) => provider.networkId),
        );
        _items = modelPickerItems(
          providers: providers,
          modelsOf: _models.stateFor,
          recents: _recents.value,
          query: _query.text,
        );
        _placeHighlight();
        final highlighted = indexOfChoice(_items, _highlight);
        return Dialog(
          child: SizedBox(
            width: modelPickerWidthIn(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ModelPickerTitleBar(),
                ModelPickerSearchField(
                  controller: _query,
                  focusNode: _field,
                  // Every keystroke re-groups the list, so the highlight has to
                  // go back to the top: a search whose first result is not the
                  // one Enter picks is a search that punishes typing.
                  onChanged: (_) => setState(() {
                    _touched = true;
                    _highlight = _firstChoice(_items);
                  }),
                ),
                _hairline(),
                Flexible(child: _list(context, providers, highlighted)),
                _hairline(),
                const ModelPickerFooter(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _hairline() =>
      Divider(height: 1, thickness: 1, color: grid.AppPalette.divider);

  /// Every provider this computer will offer, in the account's own order.
  ///
  /// Empty for every state but [GridNetworksReady] — what those states have to
  /// say is said by [providerLoadNote], as one line rather than as an absence.
  List<GridNetwork> _providers() {
    final state = _networks.state;
    if (state is! GridNetworksReady) return const [];
    return [
      for (final network in state.me.networks)
        if (_enablement.isEnabled(network.networkId)) network,
    ];
  }

  Widget _list(
    BuildContext context,
    List<GridNetwork> providers,
    int? highlighted,
  ) {
    // Two notes, one slot, and they cannot both be true: the first speaks for
    // the ACCOUNT (no providers listed yet, or signed out), the second for the
    // providers in the list still being asked for their models.
    final note =
        providerLoadNote(_networks.state) ??
        modelPickerModelsNote(providers: providers, modelsOf: _models.stateFor);
    if (_items.isEmpty) {
      return SizedBox(
        height: kModelPickerEmptyHeight,
        // "Still loading" and "your search matched nothing" are different
        // answers and must not render the same — see the skeleton rules in
        // CLAUDE.md. The account's own state speaks first because it explains
        // an empty list that no query caused.
        child: note != null
            ? Center(child: AppMenuNote(note, metrics: AppMenuRowMetrics.roomy))
            : const EmptyState.noMatches(
                message: 'No model or provider matches what you typed.',
              ),
      );
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: modelPickerListHeightIn(context)),
      child: ListView.builder(
        controller: _scroll,
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: kModelPickerListPadding),
        itemCount: _items.length + (note == null ? 0 : 1),
        itemExtentBuilder: (index, _) => index < _items.length
            ? modelPickerItemExtent(_items[index])
            : kModelPickerNoteExtent,
        itemBuilder: (context, index) => index < _items.length
            ? _row(_items[index], highlighted: index == highlighted)
            // The account's state, under the providers that did load: on a
            // failed refresh the list still holds the subscription row and whatever
            // was cached, and a panel that said nothing would look like an
            // account with one row.
            : AppMenuNote(note!, metrics: AppMenuRowMetrics.roomy),
      ),
    );
  }

  Widget _row(ModelPickerItem item, {required bool highlighted}) =>
      switch (item) {
        ModelPickerHeader(:final title) => ModelPickerGroupHeader(title),
        ModelPickerNote(:final message) => AppMenuNote(
          message,
          metrics: AppMenuRowMetrics.roomy,
        ),
        ModelPickerRow(:final choice, :final note) => AppMenuItem(
          label: item.label,
          note: note,
          metrics: AppMenuRowMetrics.roomy,
          // Two marks that mean different things and can sit on different rows:
          // the tick says where the agent IS, the highlight says what Enter
          // would do next.
          selected: choice == widget.current,
          highlighted: highlighted,
          onPressed: () => Navigator.of(context).pop(choice),
        ),
      };

  /// Opens on the row the agent is actually on, as soon as that row exists.
  ///
  /// Until it does the highlight rests on the first pickable row, so Enter
  /// always means something — and it stays there for good on an agent whose
  /// provider this account cannot name, which has no row of its own.
  void _placeHighlight() {
    if (_touched || _items.isEmpty) return;
    if (indexOfChoice(_items, widget.current) != null) {
      if (_highlight == widget.current) return;
      _highlight = widget.current;
      // After this frame: the list has no viewport to scroll until it is laid
      // out, and this runs inside the build that creates it.
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealHighlight());
      return;
    }
    _highlight ??= _firstChoice(_items);
  }

  /// The first row Enter could pick, as a choice.
  ModelChoice? _firstChoice(List<ModelPickerItem> items) =>
      _choiceAt(items, firstPickableIndex(items));

  ModelChoice? _choiceAt(List<ModelPickerItem> items, int? index) {
    if (index == null || index < 0 || index >= items.length) return null;
    final item = items[index];
    return item is ModelPickerRow ? item.choice : null;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        return _move(1);
      case LogicalKeyboardKey.arrowUp:
        return _move(-1);
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        final choice = _highlight;
        // Only a row still IN the list: a highlight whose row a late search took
        // away must answer Enter with nothing rather than with the row it used
        // to be.
        if (choice == null || indexOfChoice(_items, choice) == null) {
          return KeyEventResult.ignored;
        }
        Navigator.of(context).pop(choice);
        return KeyEventResult.handled;
    }
    // Escape included, deliberately: the dialog route already dismisses on it,
    // and a second handler here would be a second thing to keep in step with
    // the cap the title bar draws.
    return KeyEventResult.ignored;
  }

  KeyEventResult _move(int delta) {
    _touched = true;
    final from = indexOfChoice(_items, _highlight);
    final next = _choiceAt(_items, nextPickableIndex(_items, from, delta));
    // Handled either way: ↑ on the first row is the list refusing to wrap, not
    // a key for the field underneath to take as text.
    if (next == null || next == _highlight) return KeyEventResult.handled;
    setState(() => _highlight = next);
    _revealHighlight();
    return KeyEventResult.handled;
  }

  /// Scrolls the highlighted row into view — and only when it is out of it, so
  /// walking the visible rows does not drag the list under the reader.
  void _revealHighlight() {
    final index = indexOfChoice(_items, _highlight);
    if (index == null || !_scroll.hasClients) return;
    final top = _offsetOf(index);
    final bottom = top + modelPickerItemExtent(_items[index]);
    final position = _scroll.position;
    final target = bottom > position.pixels + position.viewportDimension
        ? bottom - position.viewportDimension
        : (top < position.pixels ? top : null);
    if (target == null) return;
    _scroll.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  /// Where row [index] starts, in the list's own coordinates — the same sum
  /// `itemExtentBuilder` hands the viewport, plus the padding above the first
  /// row.
  double _offsetOf(int index) {
    var offset = kModelPickerListPadding;
    for (var i = 0; i < index; i++) {
      offset += modelPickerItemExtent(_items[i]);
    }
    return offset;
  }
}
