import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../grid/grid_access.dart';
import '../../grid/grid_network.dart';
import '../../shared/theme/app_theme.dart' as grid;
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final rail = _ProviderRail(
          networks: widget.networks,
          selectedId: selected.networkId,
          defaultId: widget.defaultId,
          signedInEmail: widget.signedInEmail,
          isEnabled: widget.isEnabled,
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
          onToggleEnabled: (value) =>
              widget.onToggleEnabled(selected, value),
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
        );
        if (constraints.maxWidth < _splitBreakpoint) {
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
            SizedBox(width: _railWidth, child: _Framed(child: rail)),
            const SizedBox(width: 12),
            Expanded(
              child: _Framed(
                child: SingleChildScrollView(child: detail),
              ),
            ),
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
    required this.onToggleEnabled,
    required this.onSelect,
  });

  final List<GridNetwork> networks;
  final String selectedId;
  final String? defaultId;
  final String signedInEmail;
  final bool Function(GridNetwork) isEnabled;
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
    required this.last,
    required this.onSelect,
    required this.onToggleEnabled,
  });

  final GridNetwork network;
  final bool selected;
  final bool isDefault;
  final bool owned;
  final bool enabled;
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
    final meta = _routerSummary(widget.network);
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
                  : Border(
                      bottom: BorderSide(color: grid.AppPalette.divider),
                    ),
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
    required this.onToggleEnabled,
    required this.onMakeDefault,
    this.onRename,
    this.onDelete,
    this.onShare,
  });

  final GridNetwork network;
  final bool owned;
  final bool enabled;
  final bool isDefault;
  final bool deleting;
  final ValueChanged<bool> onToggleEnabled;
  final VoidCallback onMakeDefault;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final rule = gridAccessRule(network);
    final description = network.description?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _DetailHeader(
            network: network,
            owned: owned,
            enabled: enabled,
            isDefault: isDefault,
            onToggleEnabled: onToggleEnabled,
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: grid.AppPalette.divider),
          const SizedBox(height: 4),
          if (description.isNotEmpty)
            _DetailRow(
              label: 'Description',
              child: _PlainText(description),
            ),
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
            label: 'Router',
            child: _RouterValue(network: network),
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
          _DetailActions(
            network: network,
            owned: owned,
            enabled: enabled,
            isDefault: isDefault,
            deleting: deleting,
            onMakeDefault: onMakeDefault,
            onRename: onRename,
            onDelete: onDelete,
            onShare: onShare,
          ),
        ],
      ),
    );
  }

  /// `Mar 4, 2026` — a date a person reads, not an ISO stamp they parse.
  static String _date(DateTime value) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final local = value.toLocal();
    return '${months[local.month - 1]} ${local.day}, ${local.year}';
  }
}

/// The provider's name, its id, and the one switch that decides whether this
/// computer will use it at all.
class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.network,
    required this.owned,
    required this.enabled,
    required this.isDefault,
    required this.onToggleEnabled,
  });

  final GridNetwork network;
  final bool owned;
  final bool enabled;
  final bool isDefault;
  final ValueChanged<bool> onToggleEnabled;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
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
                  ),
                  if (owned) const _OwnedBadge(),
                  if (isDefault) const _DefaultBadge(),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              enabled ? 'ENABLED' : 'DISABLED',
              style: TextStyle(
                color: enabled
                    ? grid.AppPalette.textSecondary
                    : grid.AppPalette.textFaint,
                fontSize: 9.5,
                fontWeight: grid.AppFont.semibold,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 3),
            _ProviderSwitch(
              value: enabled,
              semanticLabel: network.displayName,
              onChanged: onToggleEnabled,
            ),
          ],
        ),
      ],
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

/// Whether the router is on, and the models it may consult — by name.
///
/// The names are the reason the panel exists: the table could only afford a
/// count, and "on · 3 models" is not an answer to "which three".
class _RouterValue extends StatelessWidget {
  const _RouterValue({required this.network});

  final GridNetwork network;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    if (!network.routerEnabled) {
      return const _PlainText(
        'Off — requests go straight to this provider’s nodes',
      );
    }
    if (network.routerAdvisors.isEmpty) {
      return const _PlainText('On, with no models listed');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _PlainText(_routerLabel(network)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            for (final advisor in network.routerAdvisors)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: grid.AppSurface.recess,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: grid.AppPalette.divider),
                ),
                child: Text(
                  advisor,
                  style: TextStyle(
                    color: grid.AppPalette.textSecondary,
                    fontSize: 11,
                    fontFamily: grid.AppFont.mono,
                    fontFamilyFallback: grid.AppFont.monoFallback,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

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

/// What can be done to the provider on screen.
///
/// "Make default" leads because it is the question the pane exists to answer;
/// Delete is last and in danger ink because it is the one thing here nobody can
/// undo. Rename and Delete are owner-only, checked here rather than left to the
/// server: a provider somebody else owns answers 403, and an action that can
/// only fail is worse than one that was never offered.
class _DetailActions extends StatelessWidget {
  const _DetailActions({
    required this.network,
    required this.owned,
    required this.enabled,
    required this.isDefault,
    required this.deleting,
    required this.onMakeDefault,
    this.onRename,
    this.onDelete,
    this.onShare,
  });

  final GridNetwork network;
  final bool owned;
  final bool enabled;
  final bool isDefault;
  final bool deleting;
  final VoidCallback onMakeDefault;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // A disabled button has to say WHY, or it reads as broken. The tooltip
        // is the whole reason this is wrapped: `Make default` greys out on a
        // provider the switch has turned off, and nothing else on the row
        // connects those two facts for somebody who did it a minute ago.
        Tooltip(
          message: !enabled
              ? 'Turn ${network.displayName} on before making it the default'
              : (isDefault
                    ? 'New agents already launch on ${network.displayName}'
                    : 'New agents will launch on ${network.displayName}'),
          child: FilledButton(
            key: Key('provider-default-${network.networkId}'),
            // Disabled on a provider this computer has switched off: new agents
            // cannot launch against something the pickers do not offer, and a
            // button that quietly turns the switch back on would undo a choice
            // the user made two clicks ago without saying so.
            onPressed: isDefault || !enabled ? null : onMakeDefault,
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
        ),
        if (onShare != null)
          _QuietButton(
            label: 'Share',
            icon: LucideIcons.userPlus300,
            onPressed: onShare!,
          ),
        if (owned && onRename != null)
          _QuietButton(
            key: Key('provider-rename-${network.networkId}'),
            label: 'Rename',
            icon: LucideIcons.pencil300,
            onPressed: onRename!,
          ),
        if (owned && onDelete != null)
          _DeleteProviderButton(
            name: network.displayName,
            deleting: deleting,
            onDelete: onDelete!,
          ),
      ],
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
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: grid.AppPalette.textSecondary,
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
    final confirmed = await showDialog<bool>(
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
          Icon(
            LucideIcons.triangleAlert300,
            size: 15,
            color: grid.AppPalette.warn,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'No provider enabled',
                  style: TextStyle(
                    color: grid.AppPalette.textPrimary,
                    fontFamily: grid.AppFont.sans,
                    fontSize: 12.5,
                    fontWeight: grid.AppFont.semibold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'New agents fall back to each engine’s own account — models '
                  'and billing come from the engine, the way the app worked '
                  'before providers.',
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

/// `router on · 3 models`, or `router off` — the panel's wording, where it sits
/// beside the label `Router` and has room to be a sentence.
String _routerLabel(GridNetwork network) {
  if (!network.routerEnabled) return 'router off';
  final count = network.routerAdvisors.length;
  return count == 0
      ? 'router on'
      : 'router on · $count model${count == 1 ? '' : 's'}';
}

/// The rail's whole meta line: `3 models`, `router on` when there are none to
/// count, `router off`. Built beside [_routerLabel] rather than by trimming it
/// at the call site, so the two cannot drift into wording the same state
/// differently.
String _routerSummary(GridNetwork network) {
  if (!network.routerEnabled) return 'router off';
  final count = network.routerAdvisors.length;
  return count == 0 ? 'router on' : '$count model${count == 1 ? '' : 's'}';
}
