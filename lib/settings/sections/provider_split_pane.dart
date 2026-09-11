import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../grid/grid_access.dart';
import '../../grid/grid_models_controller.dart';
import '../../grid/grid_network.dart';
import '../../grid/node_display.dart' show kAutoModelId, modelKey;
import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/skeleton.dart';

/// Settings ▸ Providers, as a list beside the provider it names.
///
/// **Why a split rather than the table this replaced.** The table answered
/// "which providers exist" and then hid everything else behind a per-row
/// drawer, so a person comparing two providers' router models had to open one,
/// read, close it, open the other and remember. Worse, the pane's headline card
/// repeated the chosen provider's name, access rule and owner — the same three
/// facts the selected row already carried, 200px apart, which is how a reader
/// comes to wonder whether they are two settings. The rail on the left is the
/// list; the panel on the right IS the headline, and it describes whatever the
/// rail has selected rather than whatever new agents happen to use.
///
/// ### Enabled and default are two different questions
///
/// The switch on each row answers "may my agents use this at all" and many can
/// be on at once; "Make default" answers "which one do NEW agents launch
/// against" and exactly one can be. They were one radio before, which made
/// "stop offering me this provider" impossible to say without also changing
/// what new agents use. Turning off the default hands the default to the next
/// enabled provider rather than refusing the click — a switch that sometimes
/// does nothing is worse than one that explains its consequence, and the banner
/// above the split says what happened.
///
/// There is deliberately no "No provider" row. It named a state rather than a
/// provider, sat in a list where everything else was one, and said in a row
/// what every switch being off already says. Turning them all off IS that
/// state, and [ProviderAllOffBanner] is where it is spelled out.
class ProviderSplitPane extends StatefulWidget {
  const ProviderSplitPane({
    super.key,
    required this.networks,
    required this.signedInEmail,
    required this.defaultId,
    required this.isEnabled,
    required this.onToggleEnabled,
    required this.onMakeDefault,
    this.onDelete,
    this.onRename,
    this.onShare,
    this.onAddModel,
    this.addModelRefusal,
    this.models,
    this.isDeleting,
    this.filtered = false,
  });

  /// The providers to draw, already narrowed by the pane's filter.
  final List<GridNetwork> networks;

  /// Whose session this is, so a row can say "yours" rather than printing an
  /// email the reader has to compare against their own.
  final String signedInEmail;

  /// The provider new agents launch against — null when none is set, which is
  /// what every provider being switched off leaves behind.
  final String? defaultId;

  /// Whether this computer will offer [GridNetwork] at all.
  final bool Function(GridNetwork) isEnabled;

  /// Turn a provider on or off for this computer only.
  final void Function(GridNetwork, bool) onToggleEnabled;

  /// Point new agents at this provider.
  final ValueChanged<GridNetwork> onMakeDefault;

  /// Delete a provider this account owns. Null leaves the action off every
  /// row — which is what a caller with no way to perform it should pass,
  /// rather than a callback that does nothing.
  final ValueChanged<GridNetwork>? onDelete;

  /// Rename a provider this account owns. Null leaves the action off, like
  /// [onDelete].
  final ValueChanged<GridNetwork>? onRename;

  /// Invite people to a provider. Null leaves the button off.
  final ValueChanged<GridNetwork>? onShare;

  /// Put a model ON this provider — which this pane cannot do, because serving
  /// a model is the Grid CLI's job and Share Intelligence is where that is
  /// driven. The button is a door, not an action: the caller pins the share
  /// target to this provider and opens that pane, so the reader lands on the
  /// page they wanted with the grid already chosen instead of having to know
  /// that the two screens are related. Null leaves the button off.
  final ValueChanged<GridNetwork>? onAddModel;

  /// Why `Add model` is refused, or null when it is available.
  ///
  /// A sentence rather than a bool: the button goes grey either way, and a
  /// disabled control that cannot say why reads as broken. See
  /// `GridSection._addModelRefusal` for the rule it states.
  final String? addModelRefusal;

  /// The models each provider serves. The app passes nothing and gets the
  /// singleton the model picker already fills, so opening this pane after
  /// opening that picker costs no second round trip; tests pass their own.
  final GridModelsController? models;

  /// Whether a delete is in flight for this id, so its row can say so.
  final bool Function(String)? isDeleting;

  /// Whether [networks] is narrower than the account's whole list, so the
  /// empty state can tell "no match" from "no providers at all".
  final bool filtered;

  @override
  State<ProviderSplitPane> createState() => _ProviderSplitPaneState();
}

class _ProviderSplitPaneState extends State<ProviderSplitPane> {
  /// The id the detail panel describes — an id rather than an index because the
  /// list is refiltered under it, and an index would silently come to mean a
  /// different provider on every keystroke in the filter field.
  String? _selectedId;

  /// The rail's width. Wide enough for a provider name plus its access rule on
  /// the second line, narrow enough that the detail panel keeps the majority
  /// of a 1180px settings pane.
  static const _railWidth = 292.0;

  /// Under this, the two halves stack instead of sitting side by side. Below
  /// roughly 820 the detail panel's label column and its values start wrapping
  /// into each other, which costs more than the scroll a stack adds.
  static const _splitBreakpoint = 820.0;

  GridModelsController get _models => widget.models ?? gridModelsController;

  /// The providers this pane has already asked about.
  ///
  /// ⚠️ Load-bearing, and not an optimisation. [GridModelsController.
  /// ensureLoadedFor] returns early for an answer that is ready or in flight
  /// but NOT for one that failed — so asking from `build`, or on every change
  /// to the filtered list, would re-fetch a failed provider on every keystroke
  /// and (since this pane rebuilds on the controller's own notification) spin
  /// forever. Asked once per provider; the failure carries its own Try again.
  final _asked = <String>{};

  @override
  void initState() {
    super.initState();
    // Every provider, even one already answered for: the controller's cache
    // lives as long as the app, and the whole point of coming back to this
    // pane is usually that something changed. The reader who just joined a
    // node on Share Intelligence and returned here to look at it must not be
    // shown the list from before they did — which is exactly what a cache
    // consulted and never re-asked gives them. `keepPrevious` is what stops
    // that costing a skeleton flash on every visit.
    _ask(force: true);
  }

  @override
  void didUpdateWidget(ProviderSplitPane old) {
    super.didUpdateWidget(old);
    // The list is refiltered under this pane and refreshed behind it, so a
    // provider can arrive after the first frame. NOT forced: this runs on every
    // keystroke in the filter field.
    _ask();
  }

  void _ask({bool force = false}) {
    for (final network in widget.networks) {
      final networkId = network.networkId;
      if (networkId.isEmpty) continue;
      final first = _asked.add(networkId);
      if (force) {
        unawaited(_models.refresh(networkId, keepPrevious: true));
      } else if (first) {
        _models.ensureLoadedFor(networkId);
      }
    }
  }

  /// Ask again for one provider — the Try again beside a failed list.
  void _retry(String networkId) => unawaited(_models.refresh(networkId));

  GridNetwork? get _selected {
    if (widget.networks.isEmpty) return null;
    for (final network in widget.networks) {
      if (network.networkId == _selectedId) return network;
    }
    // Selected provider filtered away, deleted, or nothing picked yet: fall
    // back to the default one, then to the first row, so the panel is never
    // blank beside a list that has rows in it.
    for (final network in widget.networks) {
      if (network.networkId == widget.defaultId) return network;
    }
    return widget.networks.first;
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    if (widget.networks.isEmpty) {
      return _EmptyProviders(filtered: widget.filtered);
    }
    final selected = _selected!;
    // Both halves read the models — the rail counts them, the panel names them
    // — so the listen happens once, here, rather than in each of them.
    return ListenableBuilder(
      listenable: _models,
      builder: (context, _) => _split(selected),
    );
  }

  Widget _split(GridNetwork selected) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < _splitBreakpoint;
        final rail = _ProviderRail(
          networks: widget.networks,
          selectedId: selected.networkId,
          defaultId: widget.defaultId,
          signedInEmail: widget.signedInEmail,
          isEnabled: widget.isEnabled,
          modelsFor: (network) => _models.stateFor(network.networkId),
          onToggleEnabled: widget.onToggleEnabled,
          onSelect: (network) =>
              setState(() => _selectedId = network.networkId),
        );
        final detail = _ProviderDetail(
          network: selected,
          owned: gridIsOwnedBy(selected, widget.signedInEmail),
          enabled: widget.isEnabled(selected),
          isDefault: selected.networkId == widget.defaultId,
          deleting: widget.isDeleting?.call(selected.networkId) ?? false,
          models: _models.stateFor(selected.networkId),
          onRetryModels: () => _retry(selected.networkId),
          onMakeDefault: () => widget.onMakeDefault(selected),
          onRename: widget.onRename == null
              ? null
              : () => widget.onRename!(selected),
          onDelete: widget.onDelete == null
              ? null
              : () => widget.onDelete!(selected),
          onShare: widget.onShare == null
              ? null
              : () => widget.onShare!(selected),
          onAddModel: widget.onAddModel == null
              ? null
              : () => widget.onAddModel!(selected),
          addModelRefusal: widget.addModelRefusal,
          // Stacked, the panel is one card inside the page's own scroll view
          // and has no bottom of its own to pin anything to.
          pinActions: !stacked,
        );
        if (stacked) {
          // Stacked: the rail keeps its own height rather than expanding, so
          // the detail below it is reachable by one scroll of the whole pane
          // instead of two scrolls that fight each other.
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Framed(child: rail),
                const SizedBox(height: 12),
                _Framed(child: detail),
              ],
            ),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: _railWidth,
              child: _Framed(child: rail),
            ),
            const SizedBox(width: 12),
            // The panel owns its own scrolling now — see [_ProviderDetail],
            // which keeps the actions on the floor of the card while the facts
            // above them scroll.
            Expanded(child: _Framed(child: detail)),
          ],
        );
      },
    );
  }
}

/// The card both halves sit in, so the split reads as two panels of one surface
/// rather than two unrelated boxes.
class _Framed extends StatelessWidget {
  const _Framed({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: grid.AppPalette.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: grid.AppPalette.divider),
      ),
      child: child,
    );
  }
}

/// The left half: every provider, one row each, each with its own switch.
class _ProviderRail extends StatelessWidget {
  const _ProviderRail({
    required this.networks,
    required this.selectedId,
    required this.defaultId,
    required this.signedInEmail,
    required this.isEnabled,
    required this.modelsFor,
    required this.onToggleEnabled,
    required this.onSelect,
  });

  final List<GridNetwork> networks;
  final String selectedId;
  final String? defaultId;
  final String signedInEmail;
  final bool Function(GridNetwork) isEnabled;
  final GridModelsState Function(GridNetwork) modelsFor;
  final void Function(GridNetwork, bool) onToggleEnabled;
  final ValueChanged<GridNetwork> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      primary: false,
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: networks.length,
      itemBuilder: (context, index) {
        final network = networks[index];
        return _ProviderRow(
          // Keyed by id so a test — and the framework's own element reuse —
          // can name one row while the list refilters under it. The name is
          // NOT unique on this pane: the detail panel prints it too.
          key: Key('provider-row-${network.networkId}'),
          network: network,
          selected: network.networkId == selectedId,
          isDefault: network.networkId == defaultId,
          owned: gridIsOwnedBy(network, signedInEmail),
          enabled: isEnabled(network),
          models: modelsFor(network),
          last: index == networks.length - 1,
          onSelect: () => onSelect(network),
          onToggleEnabled: (value) => onToggleEnabled(network, value),
        );
      },
    );
  }
}

/// One provider in the rail.
///
/// The whole row selects; only the switch toggles. The switch stops the tap so
/// turning a provider off does not also move the detail panel onto it — reading
/// about a provider and deciding to stop using it are different intentions, and
/// the pane must not conflate them the way the old table's row-as-radio did.
class _ProviderRow extends StatefulWidget {
  const _ProviderRow({
    super.key,
    required this.network,
    required this.selected,
    required this.isDefault,
    required this.owned,
    required this.enabled,
    required this.models,
    required this.last,
    required this.onSelect,
    required this.onToggleEnabled,
  });

  final GridNetwork network;
  final bool selected;
  final bool isDefault;
  final bool owned;
  final bool enabled;
  final GridModelsState models;
  final bool last;
  final VoidCallback onSelect;
  final ValueChanged<bool> onToggleEnabled;

  @override
  State<_ProviderRow> createState() => _ProviderRowState();
}

class _ProviderRowState extends State<_ProviderRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    // What this provider GIVES you, and nothing about who may join it.
    //
    // The line used to lead with the access rule — `Invite only`,
    // `domain-restricted` — which is Grid's vocabulary for membership, not an
    // answer to the question a list of PROVIDERS raises. Under a heading that
    // says Providers it reads as a property of the service rather than of the
    // roster, and `domain-restricted` was the control plane's raw wire value
    // reaching the screen at that. Who can join is a real fact and it is still
    // one row of the panel, in the sentence `gridAccessRule` writes; the rail's
    // one line goes to the models instead.
    // ⚠️ The models it counts are the ones the provider SERVES, read off the
    // relay. It used to count `router_advisors` — the models the router may
    // consult when choosing where to send a request — which is a different set,
    // usually a smaller one, printed under the same word.
    final meta = providerModelsMeta(widget.models);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onSelect,
        behavior: HitTestBehavior.opaque,
        child: Semantics(
          selected: widget.selected,
          button: true,
          label: widget.network.displayName,
          child: Container(
            decoration: BoxDecoration(
              color: widget.selected
                  ? grid.AppSurface.accentWash
                  : (_hovered ? grid.AppSurface.hoverFill : null),
              border: widget.last
                  ? null
                  : Border(bottom: BorderSide(color: grid.AppPalette.divider)),
            ),
            child: Row(
              children: [
                // The selection stripe, same 2.5px the machine rail uses so one
                // shape keeps meaning "this is the one you are looking at".
                Container(
                  width: 2.5,
                  height: 46,
                  color: widget.selected
                      ? grid.AppPalette.accentOnSurface
                      : Colors.transparent,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(11, 9, 8, 9),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.network.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: widget.enabled
                                      ? grid.AppPalette.textPrimary
                                      : grid.AppPalette.textFaint,
                                  fontFamily: grid.AppFont.sans,
                                  fontSize: 13,
                                  fontWeight: grid.AppFont.semibold,
                                ),
                              ),
                            ),
                            if (widget.isDefault) ...[
                              const SizedBox(width: 6),
                              const _DefaultBadge(),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: grid.AppPalette.textFaint,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _ProviderSwitch(
                    value: widget.enabled,
                    semanticLabel: widget.network.displayName,
                    onChanged: widget.onToggleEnabled,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The switch, sized down from Material's default so a row stays 46px.
///
/// Wrapped rather than used bare because a bare [Switch] inside a tappable row
/// lets the tap through to the row underneath on the parts of its hit box that
/// are not the track — so flicking a provider off would also select it.
class _ProviderSwitch extends StatelessWidget {
  const _ProviderSwitch({
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return GestureDetector(
      // Swallow the tap so the row behind does not also select — see the class
      // doc. `onTap` alone is not enough: the row uses an opaque hit test, so
      // this needs its own opaque box over the switch's whole footprint.
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Semantics(
        toggled: value,
        label: semanticLabel,
        child: SizedBox(
          width: 38,
          height: 24,
          child: FittedBox(
            fit: BoxFit.contain,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeTrackColor: grid.AppPalette.online,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      ),
    );
  }
}

/// `DEFAULT` — the one provider new agents launch against.
class _DefaultBadge extends StatelessWidget {
  const _DefaultBadge();

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: grid.AppSurface.accentWash,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: grid.AppPalette.accentOnSurface),
      ),
      child: Text(
        'DEFAULT',
        style: TextStyle(
          color: grid.AppPalette.accentOnSurface,
          fontSize: 8.5,
          fontWeight: grid.AppFont.semibold,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

/// The right half: everything about one provider, with nothing behind a drawer.
///
/// The old drawer held six facts and the panel holds seven; the difference is
/// that these are always on screen, which is the whole reason for the split.
/// `Provider type` is deliberately NOT among them — it is the control plane's
/// own wire value (`permissioned-public`, `private-domain`), and "Who can join"
/// two rows above is the same fact in words a reader can act on. Printing both
/// asked people to reconcile two spellings of one thing.
class _ProviderDetail extends StatelessWidget {
  const _ProviderDetail({
    required this.network,
    required this.owned,
    required this.enabled,
    required this.isDefault,
    required this.deleting,
    required this.models,
    required this.onRetryModels,
    required this.onMakeDefault,
    this.onRename,
    this.onDelete,
    this.onShare,
    this.onAddModel,
    this.addModelRefusal,
    this.pinActions = true,
  });

  final GridNetwork network;
  final bool owned;
  final bool enabled;
  final bool isDefault;
  final bool deleting;

  /// Whether the panel scrolls its own facts and keeps [_DetailActions] on the
  /// floor of the card.
  ///
  /// False where the panel has no floor: stacked under the rail it is one card
  /// inside the page's scroll view, given all the height it asks for, and an
  /// [Expanded] there would be asked to fill an unbounded box.
  final bool pinActions;
  final GridModelsState models;
  final VoidCallback onRetryModels;
  final VoidCallback onMakeDefault;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;
  final VoidCallback? onShare;
  final VoidCallback? onAddModel;

  /// See [ProviderSplitPane.addModelRefusal].
  final String? addModelRefusal;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final rule = gridAccessRule(network);
    final description = network.description?.trim() ?? '';
    // The facts, and under them what this provider serves. Everything above the
    // footer — this is what scrolls.
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _DetailHeader(
          network: network,
          owned: owned,
          enabled: enabled,
          isDefault: isDefault,
          onMakeDefault: onMakeDefault,
          onRename: onRename,
          onShare: onShare,
        ),
        const SizedBox(height: 14),
        Divider(height: 1, color: grid.AppPalette.divider),
        const SizedBox(height: 4),
        if (description.isNotEmpty)
          _DetailRow(label: 'Description', child: _PlainText(description)),
        _DetailRow(
          label: 'Status',
          child: _StatusValue(status: network.status),
        ),
        // The rule in the words the share sheet prints — never the control
        // plane's own spelling. `gridAccessRule` answers null for a rule this
        // app has no words for, and the honest thing to print then is that we
        // do not know: a wire value like `permissioned-public` under the
        // heading "Who can join" reads as a promise about who is already in,
        // in a vocabulary nobody outside the control plane shares.
        if (rule case final GridAccessRule rule)
          _DetailRow(
            label: 'Who can join',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _PlainText(rule.label),
                const SizedBox(height: 3),
                Text(
                  rule.description,
                  style: TextStyle(
                    color: grid.AppPalette.textFaint,
                    fontSize: 11.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        _DetailRow(
          label: 'Owner',
          child: _PlainText(owned ? 'You' : network.ownerEmail),
        ),
        _DetailRow(
          label: 'Provider ID',
          child: _CopyableText(value: network.networkId),
        ),
        _DetailRow(
          label: 'Signaling',
          child: network.lanSignalingUrl == null
              ? const _PlainText('—')
              : _CopyableText(value: network.lanSignalingUrl!),
        ),
        if (network.createdAt case final DateTime created)
          _DetailRow(label: 'Created', child: _PlainText(_date(created))),
        const SizedBox(height: 14),
        Divider(height: 1, color: grid.AppPalette.divider),
        const SizedBox(height: 14),
        // What this provider actually serves, which is the question the facts
        // above raise and none of them answers.
        _ProviderModels(
          models: models,
          onRetry: onRetryModels,
          onAddModel: onAddModel,
          addModelRefusal: addModelRefusal,
        ),
      ],
    );
    // ⚠️ The Align is what puts the button in the corner, not the Wrap's own
    // `alignment`. A Column aligns its children to the START, so the Wrap is
    // given a loose constraint and shrinks to fit its buttons — and aligning
    // content inside a box exactly as wide as the content moves nothing. The
    // Align takes the full width first.
    final footer = Align(
      alignment: Alignment.centerRight,
      child: _DetailActions(
        network: network,
        owned: owned,
        deleting: deleting,
        onDelete: onDelete,
      ),
    );
    final footerRule = Divider(height: 1, color: grid.AppPalette.divider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: pinActions ? MainAxisSize.max : MainAxisSize.min,
        children: [
          // The facts scroll; the two consequential buttons do not. Somebody
          // reading a provider with a long model list should not have to reach
          // the end of it to find Delete — and, more to the point, should not
          // meet Delete on the way past everything else.
          if (pinActions)
            Expanded(child: SingleChildScrollView(child: body))
          else
            body,
          const SizedBox(height: 16),
          footerRule,
          const SizedBox(height: 14),
          footer,
        ],
      ),
    );
  }

  /// `Mar 4, 2026` — a date a person reads, not an ISO stamp they parse.
  static String _date(DateTime value) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final local = value.toLocal();
    return '${months[local.month - 1]} ${local.day}, ${local.year}';
  }
}

/// The provider's name, what is true of it, and the one action that is about
/// people rather than about this computer.
///
/// **There is no switch here, and that is the point.** Every provider in the
/// rail carries one, three feet to the left, and a second copy of the same
/// control for the selected row put the same question on screen twice — one of
/// them next to a name in 20px type, which reads as the more important of the
/// two. The rail owns "will this Mac use it"; this panel describes the
/// provider. What is left of that state here is a fact, not a control: a
/// `DISABLED` badge, and only when it is.
class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.network,
    required this.owned,
    required this.enabled,
    required this.isDefault,
    required this.onMakeDefault,
    this.onRename,
    this.onShare,
  });

  final GridNetwork network;
  final bool owned;
  final bool enabled;
  final bool isDefault;

  /// Point new agents at this provider. In the header rather than at the foot
  /// of the panel because it is a statement ABOUT this provider — the same
  /// reason Share is here — and because the two of them together are what a
  /// reader does after reading the name, not after reading the model list.
  final VoidCallback onMakeDefault;

  /// Renaming is a **double-click on the name**, not a button.
  ///
  /// It is the gesture the thing itself already suggests — a file in Finder, a
  /// tab, a layer — and it costs the action row a button that was only ever
  /// reachable by owners anyway. Null, or a provider this account does not own,
  /// leaves the name inert.
  final VoidCallback? onRename;

  final VoidCallback? onShare;

  /// ⚠️ Ownership is not the whole test — see [gridCanBeRenamed]. A
  /// `private-domain` provider's name is the domain that may join it, and the
  /// control plane will happily write a new one.
  bool get _renameable =>
      owned && onRename != null && gridCanBeRenamed(network);

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final name = Text(
      network.displayName,
      style: TextStyle(
        color: enabled
            ? grid.AppPalette.textPrimary
            : grid.AppPalette.textSecondary,
        fontFamily: grid.AppFont.sans,
        fontSize: 20,
        fontWeight: grid.AppFont.semibold,
        letterSpacing: -0.35,
        height: 1.15,
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              if (!_renameable)
                // An owner who cannot rename this one is told why, rather than
                // left to conclude the double-click is broken. Everyone else
                // gets a plain name: "you do not own this" is already said by
                // the absence of YOURS.
                if (owned ? gridRenameRefusal(network) : null
                    case final String why)
                  Tooltip(
                    message: why,
                    waitDuration: const Duration(milliseconds: 500),
                    child: name,
                  )
                else
                  name
              else
                // A gesture with no affordance is a gesture nobody finds, so
                // the pointer changes and the tooltip says what it does. Both
                // only where it works.
                Tooltip(
                  message: 'Double-click to rename',
                  waitDuration: const Duration(milliseconds: 500),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.text,
                    child: GestureDetector(
                      key: Key('provider-name-${network.networkId}'),
                      onDoubleTap: onRename,
                      behavior: HitTestBehavior.opaque,
                      child: name,
                    ),
                  ),
                ),
              if (owned) const _OwnedBadge(),
              if (isDefault) const _DefaultBadge(),
              if (!enabled) const _DisabledBadge(),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Wrapped, so a narrow panel drops Share under the default button
        // instead of squeezing the name.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _MakeDefaultButton(
              network: network,
              enabled: enabled,
              isDefault: isDefault,
              onPressed: onMakeDefault,
            ),
            if (onShare != null)
              _QuietButton(
                key: Key('provider-share-${network.networkId}'),
                label: 'Share',
                icon: LucideIcons.userPlus300,
                onPressed: onShare!,
              ),
          ],
        ),
      ],
    );
  }
}

/// `DISABLED` — this computer will not offer the provider to its agents.
///
/// Drawn only when it is true. There is no `ENABLED` twin: enabled is the
/// resting state of every provider in the list, and a badge on all of them
/// would say nothing while making the one that matters harder to spot.
class _DisabledBadge extends StatelessWidget {
  const _DisabledBadge();

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: grid.AppSurface.recess,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: grid.AppPalette.divider),
      ),
      child: Text(
        'DISABLED',
        style: TextStyle(
          color: grid.AppPalette.textFaint,
          fontSize: 8.5,
          fontWeight: grid.AppFont.semibold,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

/// `YOURS` — this account owns the provider, so it may rename and delete it.
class _OwnedBadge extends StatelessWidget {
  const _OwnedBadge();

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: grid.AppSurface.recess,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: grid.AppPalette.divider),
      ),
      child: Text(
        'YOURS',
        style: TextStyle(
          color: grid.AppPalette.textSecondary,
          fontSize: 8.5,
          fontWeight: grid.AppFont.semibold,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

/// One labelled fact, label left and value right, so the panel reads as a
/// definition list rather than a form.
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.child});

  final String label;
  final Widget child;

  /// The label column. Wide enough for `Provider ID` and `Who can join` on one
  /// line at 11.5px, which are the two longest labels the panel prints.
  static const labelWidth = 118.0;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              label,
              style: TextStyle(
                color: grid.AppPalette.textFaint,
                fontSize: 11.5,
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _PlainText extends StatelessWidget {
  const _PlainText(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Text(
      value,
      style: TextStyle(
        color: grid.AppPalette.textSecondary,
        fontSize: 12.5,
        height: 1.4,
      ),
    );
  }
}

/// The PROVIDER's own status, and nothing about this computer.
///
/// ⚠️ It used to read `active · off on this computer` when the switch was off,
/// which put the same fact on screen twice inside 300px — the header directly
/// above already says DISABLED beside the switch that caused it. This row
/// answers "is the provider up", the header answers "will this Mac use it",
/// and keeping them apart is what makes each one worth reading.
class _StatusValue extends StatelessWidget {
  const _StatusValue({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final active = status == 'active';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? grid.AppPalette.online : grid.AppPalette.offline,
          ),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            status,
            style: TextStyle(
              color: grid.AppPalette.textSecondary,
              fontSize: 12.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// The models this provider serves, and the way to put another one there.
///
/// **Not a `_DetailRow`.** The rows above are facts about the provider's
/// registration — one line each, read once. This is a list that grows, carries
/// its own action, and is the reason most people open the pane at all, so it
/// gets a heading of its own under the divider instead of a 118px label with a
/// paragraph of chips hanging off it.
///
/// ⚠️ These are the models the RELAY advertises, not the `router_advisors` the
/// panel used to print under `Router`. That row is gone: it answered a question
/// about how a request is dispatched inside the grid, in the vocabulary of the
/// control plane, on a screen about which models a person can use.
class _ProviderModels extends StatelessWidget {
  const _ProviderModels({
    required this.models,
    required this.onRetry,
    this.onAddModel,
    this.addModelRefusal,
  });

  final GridModelsState models;
  final VoidCallback onRetry;
  final VoidCallback? onAddModel;

  /// See [ProviderSplitPane.addModelRefusal].
  final String? addModelRefusal;

  /// Refused, but still drawn. A button that vanishes while this computer is
  /// sharing teaches nobody why it went; a grey one with a sentence on it says
  /// what to do about it.
  bool get _refused => addModelRefusal != null;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              'MODELS',
              style: TextStyle(
                color: grid.AppPalette.textFaint,
                fontSize: 9.5,
                fontWeight: grid.AppFont.semibold,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                providerModelsMeta(models),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: grid.AppPalette.textFaint,
                  fontSize: 11.5,
                ),
              ),
            ),
            if (onAddModel != null)
              Tooltip(
                message: addModelRefusal ?? 'Lend this computer to it',
                waitDuration: const Duration(milliseconds: 400),
                // Loud on a provider that serves nothing, quiet everywhere
                // else. On a grid with models this is one more thing you could
                // do; on a grid with none it is the ONLY thing that makes the
                // provider worth having, and the panel around it is otherwise a
                // list of registration facts with an empty section at the
                // bottom. Refused, it is quiet whatever the list says — nothing
                // is gained by shouting an offer that cannot be taken.
                child: _bare && !_refused
                    ? _LoudButton(
                        key: const Key('provider-add-model'),
                        label: 'Add model',
                        icon: LucideIcons.plus300,
                        onPressed: onAddModel!,
                      )
                    : _QuietButton(
                        key: const Key('provider-add-model'),
                        label: 'Add model',
                        icon: LucideIcons.plus300,
                        onPressed: _refused ? null : onAddModel!,
                      ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        _body(),
      ],
    );
  }

  /// Whether this provider has nothing to answer with — the state `Add model`
  /// exists for, and the one it is drawn loudly in.
  bool get _bare => models is GridModelsReady && servedModels(models).isEmpty;

  Widget _body() => switch (models) {
    // Idle and Loading render the same on purpose: from the reader's side
    // "not asked yet" and "asked, no answer" are one state — nothing to show
    // and something on the way — and the pane asks for every provider as it
    // opens, so Idle lasts a frame.
    // Chip-shaped, chip-sized, and of unequal widths — a model id is not a
    // fixed-width thing, and three identical bars read as one grey slab.
    GridModelsIdle() || GridModelsLoading() => const Wrap(
      key: Key('provider-models-skeleton'),
      spacing: 5,
      runSpacing: 5,
      children: [
        Skeleton(width: 104, height: _chipHeight, radius: 4),
        Skeleton(width: 76, height: _chipHeight, radius: 4),
        Skeleton(width: 132, height: _chipHeight, radius: 4),
      ],
    ),
    GridModelsReady() when _bare => const _BareProviderNotice(),
    GridModelsReady() => Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [for (final model in servedModels(models)) _ModelChip(model)],
    ),
    // The message, not a shrug: `GridApiClient` has already turned the failure
    // into a sentence, and a provider that is merely asleep says something
    // different from one this account may not read.
    GridModelsFailed(:final message) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _PlainText(message),
        const SizedBox(height: 6),
        _LinkButton(
          key: const Key('provider-models-retry'),
          label: 'Try again',
          onPressed: onRetry,
        ),
      ],
    ),
  };
}

/// A chip's outside height: 11px mono at 1.0 leading inside 2px of padding
/// each way, plus the hairline. The loading placeholders are drawn at exactly
/// this, so the list does not jump when the names land.
const double _chipHeight = 20;

/// One model id, in mono — these are strings people copy into a config, and a
/// proportional face makes `gpt-4o-mini` and `gpt-40-mini` look alike.
class _ModelChip extends StatelessWidget {
  const _ModelChip(this.id);

  final String id;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: grid.AppSurface.recess,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: grid.AppPalette.divider),
      ),
      child: Text(
        id,
        style: TextStyle(
          color: grid.AppPalette.textSecondary,
          fontSize: 11,
          fontFamily: grid.AppFont.mono,
          fontFamilyFallback: grid.AppFont.monoFallback,
        ),
      ),
    );
  }
}

/// A retry that reads as a link: it belongs to the sentence above it, and a
/// bordered button beside a failure message competes with the panel's real
/// actions at the bottom of the pane.
class _LinkButton extends StatelessWidget {
  const _LinkButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: grid.AppPalette.accentOnSurface,
        overlayColor: grid.AppSurface.hoverFill,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: TextStyle(fontFamily: grid.AppFont.sans, fontSize: 12),
      ),
      child: Text(label),
    );
  }
}

/// What this provider can actually be asked something, out of the relay's raw
/// list.
///
/// ⚠️ **A lone `Auto` is an EMPTY provider, not a provider with one model.**
/// The relay advertises its virtual `auto` router whenever routing is on —
/// with nothing behind it to route to — so a grid nobody has joined a node to
/// still answers `/models` with one entry. Counting it read as "1 model" on a
/// provider that can answer nothing, which is the exact state this pane now
/// puts a loud button on. It is dropped from the list even when there ARE real
/// models beside it: this section says what the provider serves, and `auto` is
/// how it chooses between those, not one of them. See [kAutoModelId] and
/// `answerableModels`, which the pickers apply for the same reason.
List<String> servedModels(GridModelsState state) => switch (state) {
  GridModelsReady(:final models) => [
    for (final model in models)
      if (modelKey(model) != kAutoModelId) model,
  ],
  _ => const [],
};

/// The empty state, which is the one worth reading: it names the consequence
/// and the fix, in that order, because "0 models" is a number and not an
/// instruction.
class _BareProviderNotice extends StatelessWidget {
  const _BareProviderNotice();

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
      decoration: BoxDecoration(
        color: grid.AppSurface.accentWash,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: grid.AppPalette.accentOnSurface),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Add a model to use this provider.',
            style: TextStyle(
              color: grid.AppPalette.accentOnSurface,
              fontFamily: grid.AppFont.sans,
              fontSize: 12.5,
              fontWeight: grid.AppFont.semibold,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Nobody is serving one here yet, so an agent launched on this '
            'provider has nothing to answer it.',
            style: TextStyle(
              color: grid.AppPalette.textSecondary,
              fontSize: 11.5,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

/// The rail's one line under a provider's name: how many models it serves, or
/// what is happening instead.
///
/// Pure and shared with the panel's heading, so the count in the list and the
/// list of names beside it can never disagree about how many there are.
String providerModelsMeta(GridModelsState state) => switch (state) {
  GridModelsIdle() || GridModelsLoading() => 'Loading models…',
  GridModelsReady() when servedModels(state).isEmpty => 'No models',
  GridModelsReady() =>
    '${servedModels(state).length} '
        'model${servedModels(state).length == 1 ? '' : 's'}',
  // Deliberately not the failure's own sentence: this is a 292px line under a
  // name, and the panel prints the reason in full for whichever provider the
  // reader selects.
  GridModelsFailed() => 'Models unavailable',
};

/// A mono value with a copy affordance that appears under the pointer.
///
/// These are the two strings a person actually needs off this screen — the id
/// goes into `harness link import`, the URL into a browser — and both are long
/// enough that selecting them by hand is a chore.
class _CopyableText extends StatefulWidget {
  const _CopyableText({required this.value});

  final String value;

  @override
  State<_CopyableText> createState() => _CopyableTextState();
}

class _CopyableTextState extends State<_CopyableText> {
  bool _hovered = false;
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _copied = false;
      }),
      child: GestureDetector(
        onTap: _copy,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                widget.value,
                style: TextStyle(
                  color: grid.AppPalette.textSecondary,
                  fontSize: 11.5,
                  fontFamily: grid.AppFont.mono,
                  fontFamilyFallback: grid.AppFont.monoFallback,
                ),
              ),
            ),
            if (_hovered || _copied) ...[
              const SizedBox(width: 7),
              Icon(
                _copied ? LucideIcons.check300 : LucideIcons.copy300,
                size: 12,
                color: _copied
                    ? grid.AppPalette.online
                    : grid.AppPalette.textFaint,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.value));
    if (mounted) setState(() => _copied = true);
  }
}

/// The one irreversible thing, in the corner a reader ends on.
///
/// **Bottom right, past everything there is to read.** Delete is the only
/// action that cannot be undone, and it earns the corner a dialog puts its
/// buttons in rather than a place somebody scrolling past the models meets by
/// accident. Everything else that was in this row has gone up to the header,
/// where it sits beside the name it acts on: Share, Make default, and Rename —
/// which stopped being a button at all and became a double-click on the name.
///
/// Owner-only, checked here rather than left to the server: a provider somebody
/// else owns answers 403, and an action that can only fail is worse than one
/// that was never offered.
class _DetailActions extends StatelessWidget {
  const _DetailActions({
    required this.network,
    required this.owned,
    required this.deleting,
    this.onDelete,
  });

  final GridNetwork network;
  final bool owned;
  final bool deleting;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    if (!owned || onDelete == null) return const SizedBox.shrink();
    return _DeleteProviderButton(
      name: network.displayName,
      deleting: deleting,
      onDelete: onDelete!,
    );
  }
}

/// `Make default` — the pane's own answer to "which provider do new agents
/// launch against", in the header beside the name it would apply to.
class _MakeDefaultButton extends StatelessWidget {
  const _MakeDefaultButton({
    required this.network,
    required this.enabled,
    required this.isDefault,
    required this.onPressed,
  });

  final GridNetwork network;
  final bool enabled;
  final bool isDefault;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    // A disabled button has to say WHY, or it reads as broken. The tooltip is
    // the whole reason this is wrapped: `Make default` greys out on a provider
    // the RAIL's switch has turned off, and nothing beside it connects those
    // two facts for somebody who did it a minute ago.
    return Tooltip(
      message: !enabled
          ? 'Turn ${network.displayName} on before making it the default'
          : (isDefault
                ? 'New agents already launch on ${network.displayName}'
                : 'New agents will launch on ${network.displayName}'),
      child: FilledButton(
        key: Key('provider-default-${network.networkId}'),
        // Disabled on a provider this computer has switched off: new agents
        // cannot launch against something the pickers do not offer, and a
        // button that quietly turned the switch back on would undo a choice the
        // user made two clicks ago without saying so.
        onPressed: isDefault || !enabled ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: grid.AppPalette.accentOnSurface,
          disabledBackgroundColor: grid.AppSurface.recess,
          disabledForegroundColor: grid.AppPalette.textFaint,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: TextStyle(
            fontFamily: grid.AppFont.sans,
            fontSize: 12.5,
            fontWeight: grid.AppFont.semibold,
          ),
        ),
        child: Text(isDefault ? 'Current default' : 'Make default'),
      ),
    );
  }
}

/// The same button as [_QuietButton], wearing the accent.
///
/// Used for exactly one thing — `Add model` on a provider that serves none —
/// where the action is not one option among several but the only one that
/// makes the screen worth being on. It is the accent rather than a bigger
/// quiet button because on this panel blue already means "the thing to press",
/// and the panel's other accent button (`Make default`) is greyed out on a
/// provider nobody can launch against anyway.
class _LoudButton extends StatelessWidget {
  const _LoudButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: grid.AppPalette.accentOnSurface,
        overlayColor: const Color(0x1FFFFFFF),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: TextStyle(
          fontFamily: grid.AppFont.sans,
          fontSize: 12.5,
          fontWeight: grid.AppFont.semibold,
        ),
      ),
      icon: Icon(icon, size: 13),
      label: Text(label),
    );
  }
}

/// A secondary action: reading ink, a hairline box, no fill until hover.
class _QuietButton extends StatelessWidget {
  const _QuietButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;

  /// Null draws it disabled — see [_ProviderModels._refused] for the one case.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: grid.AppPalette.textSecondary,
        disabledForegroundColor: grid.AppPalette.textFaint,
        // Restated: `styleFrom` replaces the theme's style, and with NoSplash
        // app-wide a button without this has no hover state at all.
        overlayColor: grid.AppSurface.hoverFill,
        side: BorderSide(color: grid.AppPalette.divider),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: TextStyle(fontFamily: grid.AppFont.sans, fontSize: 12.5),
      ),
      icon: Icon(icon, size: 13),
      label: Text(label),
    );
  }
}

/// The one irreversible action on this pane: it deletes the provider for
/// everyone on it, not just for this computer.
class _DeleteProviderButton extends StatelessWidget {
  const _DeleteProviderButton({
    required this.name,
    required this.deleting,
    required this.onDelete,
  });

  final String name;
  final bool deleting;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return OutlinedButton.icon(
      key: Key('provider-delete-$name'),
      onPressed: deleting ? null : () => _confirm(context),
      style: OutlinedButton.styleFrom(
        foregroundColor: grid.AppPalette.dangerFill,
        overlayColor: grid.AppPalette.dangerFill,
        side: BorderSide(color: grid.AppPalette.divider),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: TextStyle(fontFamily: grid.AppFont.sans, fontSize: 12.5),
      ),
      icon: deleting
          ? const SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(LucideIcons.trash2300, size: 13),
      label: Text(deleting ? 'Deleting…' : 'Delete'),
    );
  }

  /// Names what is lost rather than asking "are you sure?" — the question adds
  /// nothing the reader did not already know, and trains people to dismiss it.
  Future<void> _confirm(BuildContext context) async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this provider?'),
        content: SizedBox(
          width: 360,
          child: Text(
            'This permanently deletes "$name" and removes everyone on it. '
            "This can't be undone.",
            style: TextStyle(
              fontFamily: grid.AppFont.sans,
              fontSize: 13.5,
              height: 1.4,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: grid.AppPalette.textSecondary,
              overlayColor: grid.AppSurface.hoverFill,
            ),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('provider-delete-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: grid.AppPalette.dangerFill,
              overlayColor: const Color(0x1FFFFFFF),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) onDelete();
  }
}

/// Said out loud when every provider is switched off, because the consequence
/// lands on agents launched later rather than on this screen — nothing here
/// would otherwise look wrong.
///
/// This is what replaced the old "No provider" row. That row named a state in a
/// list of providers, which put a non-provider among providers; this says the
/// same thing where a consequence belongs, above the thing that caused it.
///
/// ⚠️ It STATES, it does not warn. Turning every provider off is a supported
/// way to run the app — agents launch, work gets done, the engines bill their
/// own subscriptions — so this carries an info glyph and names what IS
/// happening. It used to open with an amber triangle over the words "No
/// provider enabled", which described a deliberate choice as a fault and
/// described it by what was missing.
class ProviderAllOffBanner extends StatelessWidget {
  const ProviderAllOffBanner({super.key});

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
      decoration: BoxDecoration(
        color: grid.AppSurface.recess,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: grid.AppPalette.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ⚠️ An info glyph, not a warning triangle. Every provider being off
          // is a supported setup that keeps working, not a fault: agents still
          // launch and still bill the subscriptions on this computer. The
          // amber triangle told somebody who had just made that choice on
          // purpose that they had broken something.
          Icon(LucideIcons.info300, size: 15, color: grid.AppPalette.textFaint),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Running on subscriptions',
                  style: TextStyle(
                    color: grid.AppPalette.textPrimary,
                    fontFamily: grid.AppFont.sans,
                    fontSize: 12.5,
                    fontWeight: grid.AppFont.semibold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'New agents run on each engine’s own subscription on this '
                  'computer — models and billing come from the engine, the way '
                  'the app worked before providers.',
                  style: TextStyle(
                    color: grid.AppPalette.textSecondary,
                    fontSize: 11.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Nothing to show — either the filter matched none, or this account is on no
/// provider at all. The two are different problems and say so.
class _EmptyProviders extends StatelessWidget {
  const _EmptyProviders({required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return _Framed(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
        alignment: Alignment.center,
        child: Text(
          filtered
              ? 'No provider matches that filter.'
              : 'This account is not on a provider yet. Join one from the '
                    'Grid app, then reload here.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: grid.AppPalette.textFaint,
            fontSize: 12.5,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

/// The split, waiting on its answer, in the shape of the answer.
///
/// A rail of placeholder rows beside an empty panel — the same two boxes the
/// loaded pane draws, so nothing moves sideways when the providers land. See
/// `shared/widgets/skeleton.dart` for why this is a skeleton and not a spinner.
class ProviderSplitPaneSkeleton extends StatelessWidget {
  const ProviderSplitPaneSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final rail = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < 4; index++)
              Container(
                height: 46,
                padding: const EdgeInsets.fromLTRB(13, 9, 10, 9),
                decoration: BoxDecoration(
                  border: index == 3
                      ? null
                      : Border(
                          bottom: BorderSide(color: grid.AppPalette.divider),
                        ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          SizedBox(width: 92, child: SkeletonLine(height: 11)),
                          SizedBox(height: 5),
                          SizedBox(width: 132, child: SkeletonLine(height: 9)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 34, child: SkeletonLine(height: 18)),
                  ],
                ),
              ),
          ],
        );
        final detail = Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: const [
              SizedBox(width: 160, child: SkeletonLine(height: 20)),
              SizedBox(height: 20),
              SizedBox(width: 260, child: SkeletonLine(height: 12)),
              SizedBox(height: 16),
              SizedBox(width: 220, child: SkeletonLine(height: 12)),
              SizedBox(height: 16),
              SizedBox(width: 280, child: SkeletonLine(height: 12)),
              SizedBox(height: 16),
              SizedBox(width: 200, child: SkeletonLine(height: 12)),
            ],
          ),
        );
        if (constraints.maxWidth < _ProviderSplitPaneState._splitBreakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Framed(child: rail),
              const SizedBox(height: 12),
              _Framed(child: detail),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: _ProviderSplitPaneState._railWidth,
              child: _Framed(child: rail),
            ),
            const SizedBox(width: 12),
            Expanded(child: _Framed(child: detail)),
          ],
        );
      },
    );
  }
}
