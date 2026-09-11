import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../analytics/analytics.dart';
import '../../grid/grid_networks_controller.dart';
import '../../grid/grid_selection_store.dart';
import '../../grid/provider_enablement_store.dart';
import '../../settings/settings_screen.dart';
import '../../settings/settings_section.dart';
import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/widgets/app_menu.dart';
import '../../state/app_state.dart';
import '../grid_target_pill.dart' show gridTargetMenuOptions;

/// Which provider this computer is on, at the left end of the status rail.
///
/// ⚠️ **Not "what new agents run on" any more.** That is what this pill was
/// added to answer, and it is no longer the question it answers: a new agent
/// starts on the engine's own login whatever is picked here. What the choice
/// still decides is what the usage figures beside it count, what Share
/// Intelligence offers first, and which provider the usage-limit offer moves
/// agents to.
///
/// **The rail said the consequence and never the cause.** Everything else on
/// this strip is a measurement — how much of a rate limit is spent, how many
/// machines are up — and a person reading `2% used` was given no way to know
/// whose 2% it was. This says it in the two words the answer actually takes:
/// a provider's name, or `This computer` when there is none and the engines are
/// spending their own accounts.
///
/// ### Why the words are "This computer"
///
/// Because they say what IS rather than what is missing. With no provider
/// chosen the agents bill whatever the engines are already signed in with here
/// — which is also what the figures to the right of this pill are counting, so
/// the two halves of the strip describe one thing.
///
/// ⚠️ The picker inside this menu once said `No provider` for the same state,
/// on the theory that a menu row may be named for what it is NOT while a
/// readout must say what IS. Seen together that failed: clicking a pill
/// labelled one thing and finding the tick beside another makes a reader match
/// up two names for one state. Both say the same thing now — see
/// [kNoGridTargetLabel], which this aliases.
///
/// ⚠️ Both said `Subscription` for a while, which was the same failure one step
/// on: that word names a subscription, and an account signed in with an API key
/// is this state too. See [kNoGridTargetLabel] for why the name moved to where
/// the credential lives rather than what kind it is.
///
/// The pill is a button because the alternative was worse: the name was already
/// on the rail when a provider was chosen (the old `_GridMark`), and it was not
/// clickable, so the one place the answer appeared was the one place it could
/// not be changed.
class RailProviderPill extends StatefulWidget {
  const RailProviderPill({
    super.key,
    required this.notifier,
    this.networks,
    this.selection,
    this.enablement,
    this.fallbackName,
  });

  /// Settings needs it, and the rail does not otherwise hold one.
  final AppNotifier notifier;

  /// All three injected by tests. The app uses the shared singletons, which is
  /// what lets this pill and Settings ▸ Providers see the same choice.
  final GridNetworksController? networks;
  final GridSelectionStore? selection;
  final ProviderEnablementStore? enablement;

  /// What to print when the selection store has an id but no name for it —
  /// the overview controller knows the name because it fetched the grid, and
  /// the store may not if the choice was made before the name was known.
  /// Null where there is no such fallback (the no-provider case).
  final String? fallbackName;

  @override
  State<RailProviderPill> createState() => _RailProviderPillState();
}

class _RailProviderPillState extends State<RailProviderPill> {
  /// Held because [AppMenuItem] does not close the panel for you.
  final _menu = MenuController();

  GridNetworksController get _networks =>
      widget.networks ?? gridNetworksController;

  GridSelectionStore get _selection => widget.selection ?? gridSelectionStore;

  ProviderEnablementStore get _enablement =>
      widget.enablement ?? providerEnablementStore;

  /// The panel's width, stated once — read by [AppMenu.style] and by the note
  /// at the top of the list, which cannot wrap without it.
  static const double _panelMaxWidth = 304;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return ValueListenableBuilder<GridSelection>(
      valueListenable: _selection,
      builder: (context, chosen, _) => ListenableBuilder(
        // Both, because an open menu has to stay current: the list arrives from
        // the controller, and a provider switched off in Settings has to leave
        // the menu while Settings is still open behind it.
        listenable: Listenable.merge([_networks, _enablement]),
        builder: (context, _) => MenuAnchor(
          controller: _menu,
          // Opens UPWARD: the rail is the window's bottom edge, and a menu that
          // dropped would open off-screen.
          alignmentOffset: const Offset(0, 6),
          style: grid.AppMenu.style(
            minWidth: 232,
            maxWidth: _panelMaxWidth,
            maxHeight: 420,
          ),
          // Cheap on every open: only the first one fetches.
          onOpen: _networks.ensureLoaded,
          menuChildren: _rows(chosen),
          builder: (context, controller, _) => _Pill(
            open: controller.isOpen,
            label: chosen.hasGrid
                ? (chosen.networkName?.trim().isNotEmpty ?? false
                      ? chosen.label
                      : (widget.fallbackName ?? chosen.label))
                : kRailSubscriptionLabel,
            onProvider: chosen.hasGrid,
            onTap: controller.isOpen ? controller.close : controller.open,
          ),
        ),
      ),
    );
  }

  List<Widget> _rows(GridSelection chosen) => [
    // ⚠️ This used to read "New agents only", and that stopped being true: a
    // new agent starts on the engine's own login whatever is picked here (see
    // `widgets/new_agent_dialog.dart`). The note now says where the choice is
    // actually felt, and where an agent is moved onto a provider instead.
    const AppMenuNote(
      'This is what the figures beside it count, and what Share Intelligence '
      'offers first. A new agent starts on its engine’s own login — move one '
      'onto a provider from that agent’s model menu.',
      panelWidth: _panelMaxWidth,
    ),
    const AppMenuDivider(),
    for (final option in gridTargetMenuOptions(
      _networks.state,
      isEnabled: _enablement.isEnabled,
    ))
      if (option.enabled)
        AppMenuItem(
          label: option.label,
          // Only the subscription row carries one, and only because it is the
          // one row whose name does not say where the work is billed. A
          // provider's row is named after the provider, which is the whole
          // answer; this row is named after a kind of account, and `on this
          // computer` is what tells a reader whose.
          //
          // ⚠️ Which is why it DROPS once that row names the machine: with the
          // label reading `MacBook-Pro.local`, the note repeats in weaker ink
          // what the row already says in stronger, and the reason the note
          // exists has been answered by the name.
          note:
              option.networkId == null &&
                  thisComputerLabel == kNoGridTargetLabel
              ? 'on this computer'
              : null,
          selected: option.networkId == chosen.networkId,
          onPressed: () {
            _menu.close();
            unawaited(_pick(option.networkId, option.label));
          },
        )
      else
        AppMenuNote(option.label),
    if (_networks.state is GridNetworksFailed)
      AppMenuItem(
        icon: LucideIcons.refreshCw300,
        label: 'Try again',
        onPressed: () {
          _menu.close();
          unawaited(_networks.refresh());
        },
      ),
    const AppMenuDivider(),
    AppMenuItem(
      key: const Key('rail-provider-settings-item'),
      icon: LucideIcons.settings300,
      label: 'Provider settings…',
      onPressed: () {
        _menu.close();
        unawaited(
          showSettingsScreen(
            context,
            widget.notifier,
            gridNetworks: _networks,
            initialSection: SettingsSection.grid,
            source: 'rail_menu',
          ),
        );
      },
    ),
  ];

  /// Point new agents somewhere else. A null [networkId] is the picker's own
  /// "no provider" row, which is this readout's `This computer`.
  Future<void> _pick(String? networkId, String label) async {
    analytics.gridPicked(source: 'rail', networkId: networkId);
    await (networkId == null
        ? _selection.clear()
        : _selection.selectNetwork(networkId: networkId, networkName: label));
  }
}

/// What the rail calls running on no provider.
///
/// ⚠️ **An alias now, not a second word.** These were deliberately different
/// once — the pill said one thing and the picker said `No provider` — on the
/// theory that a readout states what IS while a menu row may be named for what
/// it is NOT. Seen side by side that theory failed: clicking a pill labelled
/// one way and finding the tick beside another makes a reader match up two
/// names for one state, and the menu's name called a deliberate setup an
/// absence.
///
/// Kept as a name because the rail reads better for it, but it resolves to
/// [kNoGridTargetLabel] so the pill and the picker cannot drift apart again.
///
/// ⚠️ The NAME still says `Subscription`; the value no longer does. That word
/// was the label once, and the state it stands for covers an API key just as
/// much (see [kNoGridTargetLabel]), so read this as "the rail's word for
/// running on no provider" rather than as a claim about which credential it is.
/// Left alone deliberately: it is referenced from tests, and renaming an alias
/// to fix a comment is not worth breaking their compile over.
///
/// ⚠️ No longer `const`: it resolves to [thisComputerLabel], which is this
/// machine's own name once startup has found one and [kNoGridTargetLabel]
/// until then. The pill prints the machine rather than the words "This
/// computer" — a reader with several machines in the sidebar should see the
/// same name here that names the row they are working on.
String get kRailSubscriptionLabel => thisComputerLabel;

/// The pill itself — a bolt, a name, a caret.
///
/// Sized to the rail's 26px: a 20px box inside it, which leaves 3px of air
/// above and below and lands the text on the same baseline as every figure to
/// its right.
class _Pill extends StatefulWidget {
  const _Pill({
    required this.open,
    required this.label,
    required this.onProvider,
    required this.onTap,
  });

  final bool open;
  final String label;

  /// Whether a provider is actually chosen — the bolt lights only then, so the
  /// rail can be read at a glance without reading the word.
  final bool onProvider;
  final VoidCallback onTap;

  @override
  State<_Pill> createState() => _PillState();
}

class _PillState extends State<_Pill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final lit = widget.open || _hovered;
    return Semantics(
      button: true,
      label: widget.onProvider
          ? 'this computer’s provider is ${widget.label}'
          : 'this computer is on no provider; engines use their own accounts',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: lit ? grid.AppSurface.hoverFill : null,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              // ⚠️ NOT `mainAxisSize.min`, which is what a pill would normally
              // be. A min-sized Row measures against its children instead of
              // its constraints, so the `Flexible` below is never asked to
              // shrink and the block demands whatever the name wanted — which
              // is the overflow, and why three different fixed caps each
              // cleared one shape of rail and broke another. Sized to the
              // constraint the flex finally means something, and the pill's own
              // width still comes from its content because the `Flexible`
              // wrapping this whole widget is `loose`.
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.zap300,
                  size: 11,
                  // Lit only on a real provider. With none the glyph stays, so
                  // the pill keeps its width and the figures beside it do not
                  // shift when a provider is picked.
                  color: widget.onProvider
                      ? grid.AppPalette.accentOnSurface
                      : grid.AppPalette.textFaint,
                ),
                const SizedBox(width: 6),
                // ⚠️ The cap here is a GUARD, not the layout. It used to be
                // 112 — measured to fit `autonomous.ai` exactly — and that was
                // the visible bug: a `ConstrainedBox` binds at EVERY width, and
                // `Flexible`'s loose fit only ever lets a child take LESS than
                // its share, never more than the box. So the name was clipped
                // to 112 on a 1900px rail with 465px of empty strip beside it.
                //
                // The flex is what handles a short rail; this number only stops
                // one absurd provider name from eating the whole left end
                // before the flex has anything to divide. Set well clear of any
                // real name so it never decides an ordinary layout.
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.onProvider
                            ? grid.AppPalette.textPrimary
                            : grid.AppPalette.textSecondary,
                        fontFamily: grid.AppFont.sans,
                        fontSize: 11.5,
                        fontWeight: widget.onProvider
                            ? grid.AppFont.semibold
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Icon(
                  LucideIcons.chevronDown300,
                  size: 10,
                  color: grid.AppPalette.textFaint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
