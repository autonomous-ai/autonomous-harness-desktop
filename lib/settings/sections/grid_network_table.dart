import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../grid/grid_network.dart';
import '../../shared/theme/app_theme.dart' as grid;

/// Every grid this account can reach, as one table you pick from.
///
/// A table rather than the stack of cards this pane used to be. The cards were
/// four unrelated facts and three lines of small print each, repeated per grid,
/// with the *chosen* one marked only by the words inside a pill — so the one
/// question the screen exists to answer ("which grid do new agents use?") was
/// the hardest thing on it to see. Rows put the same facts in columns the eye
/// can run down, and the pick is a radio with a stripe down its edge.
///
/// ### Choosing and reading are separate gestures
///
/// The row is the radio: clicking anywhere on it picks that grid. The chevron
/// at the end opens the drawer with the id, the signaling URL and the router's
/// advisors — and it explicitly does **not** change the selection, because
/// wanting to read a grid's id is not wanting to launch agents on it. The card
/// layout could not offer that distinction: everything was always open, so the
/// pane cost twelve lines of mono ink to show four names.
class GridNetworkTable extends StatefulWidget {
  const GridNetworkTable({
    super.key,
    required this.networks,
    required this.signedInEmail,
    required this.selectedId,
    required this.onUse,
    this.filtered = false,
  });

  /// The grids to draw, already narrowed by the pane's filter.
  final List<GridNetwork> networks;

  /// Whose session this is, so a row can say "yours" rather than printing an
  /// email the reader has to compare against their own.
  final String signedInEmail;

  /// The grid new agents launch against — null for "each engine's own login".
  final String? selectedId;

  /// Pick a grid, or null to go back to the engines' own logins.
  final ValueChanged<GridNetwork?> onUse;

  /// Whether [networks] is a filtered view, so an empty table can say which
  /// kind of nothing it is showing.
  final bool filtered;

  @override
  State<GridNetworkTable> createState() => _GridNetworkTableState();
}

class _GridNetworkTableState extends State<GridNetworkTable> {
  /// The rows whose drawer is open. Keyed by network id rather than by index
  /// so filtering the list does not open somebody else's drawer.
  final _open = <String>{};

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _Columns.forWidth(constraints.maxWidth);
        return Container(
          decoration: BoxDecoration(
            color: grid.AppGlass.surfaceFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: grid.AppGlass.hair),
            boxShadow: grid.AppGlass.shadow,
          ),
          // Clipped so the first row's fill and the last row's hover both stop
          // at the container's curve instead of squaring off its corners.
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Column(
              children: [
                _HeaderRow(columns: columns),
                // The "no grid" option is part of the same radio group and is
                // deliberately outside the scroll view: it is never filtered
                // away, so the way back to the engines' own logins cannot be
                // hidden by a query that happens to match nothing.
                _NoGridRow(
                  selected: widget.selectedId == null,
                  onTap: () => widget.onUse(null),
                ),
                Expanded(child: _rows(columns)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _rows(_Columns columns) {
    if (widget.networks.isEmpty) {
      return _EmptyRows(filtered: widget.filtered);
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: widget.networks.length,
      itemBuilder: (context, index) {
        final network = widget.networks[index];
        return _NetworkRow(
          network: network,
          columns: columns,
          owned: network.isOwnedBy(widget.signedInEmail),
          selected: network.networkId == widget.selectedId,
          expanded: _open.contains(network.networkId),
          last: index == widget.networks.length - 1,
          onUse: () => widget.onUse(network),
          onToggleDetails: () => setState(() {
            if (!_open.remove(network.networkId)) {
              _open.add(network.networkId);
            }
          }),
        );
      },
    );
  }
}

/// Which columns are worth their width right now.
///
/// Measured against the TABLE, not the window: this pane sits beside a 260px
/// rail inside 24px padding, so a window wide enough to show everything still
/// hands the table about 250px less than the number a window breakpoint would
/// be reasoning about. Every column that goes lives on in the row's drawer, so
/// narrowing the window hides nothing — it only moves it one click away.
@immutable
class _Columns {
  const _Columns({
    required this.router,
    required this.signaling,
    required this.status,
  });

  final bool router;
  final bool signaling;
  final bool status;

  static _Columns forWidth(double width) => _Columns(
    status: width >= 560,
    router: width >= 700,
    signaling: width >= 860,
  );

  // Flex weights for the columns that stretch. Name and access carry two lines
  // each and get the room; signaling is a URL that may ellipsize.
  static const int nameFlex = 32;
  static const int accessFlex = 28;
  static const int routerFlex = 15;
  static const int signalingFlex = 25;

  // Fixed cells. The pick and the chevron are targets, not text.
  static const double pickWidth = 38;
  static const double statusWidth = 92;
  static const double detailsWidth = 38;
}

/// The column captions: uppercase micro-type, the app's one shape for a label
/// that names a column rather than a value.
class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.columns});

  final _Columns columns;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: grid.AppPalette.divider)),
      ),
      child: Row(
        children: [
          const SizedBox(width: _Columns.pickWidth),
          const Expanded(flex: _Columns.nameFlex, child: _Caption('Grid')),
          const Expanded(
            flex: _Columns.accessFlex,
            child: _Caption('Your access'),
          ),
          if (columns.router)
            const Expanded(
              flex: _Columns.routerFlex,
              child: _Caption('Router'),
            ),
          if (columns.signaling)
            const Expanded(
              flex: _Columns.signalingFlex,
              child: _Caption('Signaling'),
            ),
          if (columns.status)
            const SizedBox(
              width: _Columns.statusWidth,
              child: _Caption('Status'),
            ),
          const SizedBox(width: _Columns.detailsWidth),
        ],
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: grid.AppPalette.textFaint,
          fontSize: 10,
          fontWeight: grid.AppFont.semibold,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// The first row of the radio group: no grid at all.
///
/// It was a menu item in the sidebar and nothing at all in Settings, which made
/// the pane a one-way door — you could put agents on a grid here but only take
/// them off somewhere else. As a row it is simply the option it always was.
class _NoGridRow extends StatelessWidget {
  const _NoGridRow({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return _RowSurface(
      selected: selected,
      onTap: onTap,
      semanticsLabel: "Each engine's own login",
      child: Row(
        children: [
          SizedBox(
            width: _Columns.pickWidth,
            child: Center(child: _PickDot(selected: selected)),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Each engine's own login",
                    style: TextStyle(
                      color: grid.AppPalette.textPrimary,
                      fontSize: 13,
                      fontWeight: grid.AppFont.medium,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "Claude Code signs in with its own account — how the app "
                    'worked before grids',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: grid.AppPalette.textFaint,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: _Columns.detailsWidth),
        ],
      ),
    );
  }
}

/// One grid.
class _NetworkRow extends StatelessWidget {
  const _NetworkRow({
    required this.network,
    required this.columns,
    required this.owned,
    required this.selected,
    required this.expanded,
    required this.last,
    required this.onUse,
    required this.onToggleDetails,
  });

  final GridNetwork network;
  final _Columns columns;
  final bool owned;
  final bool selected;
  final bool expanded;
  final bool last;
  final VoidCallback onUse;
  final VoidCallback onToggleDetails;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RowSurface(
          selected: selected,
          onTap: onUse,
          semanticsLabel: 'Use ${network.displayName} for new agents',
          // The drawer under an open row carries the divider instead, so the
          // row and its details read as one block rather than two.
          divider: !expanded,
          child: Row(
            children: [
              SizedBox(
                width: _Columns.pickWidth,
                child: Center(child: _PickDot(selected: selected)),
              ),
              Expanded(
                flex: _Columns.nameFlex,
                child: _NameCell(network: network, owned: owned),
              ),
              Expanded(
                flex: _Columns.accessFlex,
                child: _AccessCell(network: network, owned: owned),
              ),
              if (columns.router)
                Expanded(
                  flex: _Columns.routerFlex,
                  child: _RouterCell(network: network),
                ),
              if (columns.signaling)
                Expanded(
                  flex: _Columns.signalingFlex,
                  child: _MonoCell(
                    value: _shortUrl(network.lanSignalingUrl) ?? '—',
                  ),
                ),
              if (columns.status)
                SizedBox(
                  width: _Columns.statusWidth,
                  child: _StatusCell(status: network.status),
                ),
              SizedBox(
                width: _Columns.detailsWidth,
                child: Center(
                  child: _DetailsToggle(
                    expanded: expanded,
                    label: network.displayName,
                    onPressed: onToggleDetails,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (expanded)
          _DetailDrawer(
            network: network,
            owned: owned,
            selected: selected,
            last: last,
          ),
      ],
    );
  }
}

/// The fill, the hover, the focus ring and the selection stripe — everything a
/// row shares whatever it holds.
class _RowSurface extends StatelessWidget {
  const _RowSurface({
    required this.selected,
    required this.onTap,
    required this.child,
    required this.semanticsLabel,
    this.divider = true,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final String semanticsLabel;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      label: semanticsLabel,
      child: Material(
        color: selected ? grid.AppSurface.accentWash : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: grid.AppSurface.hoverFill,
          // No splash: the app disables Material's ripple everywhere else, and
          // a row that ripples in a settings table reads as Android.
          splashFactory: NoSplash.splashFactory,
          child: Stack(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: divider
                    ? BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: grid.AppPalette.divider),
                        ),
                      )
                    : null,
                child: child,
              ),
              // The mark that was missing: a stripe down the chosen row's edge,
              // the same one the settings rail puts beside the open section.
              if (selected)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 2.5,
                    color: grid.AppPalette.accentOnSurface,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The radio itself.
///
/// Drawn rather than Material's [Radio], which arrives 40px wide with its own
/// tap target, its own ripple and its own accent, none of which match a row
/// that is already the target.
class _PickDot extends StatelessWidget {
  const _PickDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return AnimatedContainer(
      duration: grid.AppMotion.hover,
      curve: grid.AppMotion.curve,
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? grid.AppPalette.accentOnSurface : Colors.transparent,
        border: Border.all(
          color: selected
              ? grid.AppPalette.accentOnSurface
              : grid.AppPalette.textFaint,
          width: 1.5,
        ),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 5.5,
                height: 5.5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: grid.AppGlass.surfaceFill,
                ),
              ),
            )
          : null,
    );
  }
}

/// Name over id. The id stays on the row — it is how a grid is identified in
/// every log and every CLI flag — but at mono 11 in faint ink, under the name
/// rather than beside it.
class _NameCell extends StatelessWidget {
  const _NameCell({required this.network, required this.owned});

  final GridNetwork network;
  final bool owned;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  network.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: grid.AppPalette.textPrimary,
                    fontSize: 13,
                    fontWeight: grid.AppFont.semibold,
                    letterSpacing: -0.05,
                  ),
                ),
              ),
              if (owned) ...[const SizedBox(width: 8), const _OwnedBadge()],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            network.networkId,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: grid.AppPalette.textFaint,
              fontSize: 11,
              fontFamily: grid.AppFont.mono,
              fontFamilyFallback: grid.AppFont.monoFallback,
            ),
          ),
        ],
      ),
    );
  }
}

/// "yours" — an outline in the app's owner teal.
///
/// A word, not an email: the card printed `ownerEmail` on every grid and left
/// the reader to compare it against their own address, which is a lookup the
/// app can do for them.
class _OwnedBadge extends StatelessWidget {
  const _OwnedBadge();

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: grid.AppPalette.teal.withValues(alpha: 0.9)),
      ),
      child: Text(
        'YOURS',
        style: TextStyle(
          color: grid.AppPalette.teal,
          fontSize: 9.5,
          fontWeight: grid.AppFont.semibold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Roles and grid type as tags, the owner's address under them.
///
/// The two shapes say two different things, which the old single row of pills
/// could not: a role is something this account HOLDS (outlined, in reading
/// ink), a type is what the grid IS (filled, quiet).
class _AccessCell extends StatelessWidget {
  const _AccessCell({required this.network, required this.owned});

  final GridNetwork network;
  final bool owned;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final roles = network.member?.roles ?? const <String>[];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 5,
            runSpacing: 4,
            children: [
              for (final role in roles) _Tag(label: role, outlined: true),
              _Tag(label: network.networkType),
              if (network.accessDomain != null)
                _Tag(label: '@${network.accessDomain}'),
            ],
          ),
          if (!owned) ...[
            const SizedBox(height: 3),
            Text(
              network.ownerEmail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: grid.AppPalette.textFaint, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, this.outlined = false});

  final String label;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: outlined ? null : grid.AppSurface.selectedFill,
        borderRadius: BorderRadius.circular(5),
        border: outlined ? Border.all(color: grid.AppGlass.hair) : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: outlined
              ? grid.AppPalette.textPrimary
              : grid.AppPalette.textSecondary,
          fontSize: 11,
        ),
      ),
    );
  }
}

/// Whether the router is on, and how many models it may consult — never the
/// models themselves.
///
/// The card printed the whole advisor list inline, which made one grid's row
/// three lines tall while its neighbours were one. The names are in the drawer,
/// where a list is allowed to be a list.
class _RouterCell extends StatelessWidget {
  const _RouterCell({required this.network});

  final GridNetwork network;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final count = network.routerAdvisors.length;
    if (!network.routerEnabled) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          'off',
          style: TextStyle(color: grid.AppPalette.textFaint, fontSize: 12),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        count == 0 ? 'on' : 'on · $count model${count == 1 ? '' : 's'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: grid.AppPalette.textSecondary, fontSize: 12),
      ),
    );
  }
}

class _MonoCell extends StatelessWidget {
  const _MonoCell({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: grid.AppPalette.textFaint,
          fontSize: 11,
          fontFamily: grid.AppFont.mono,
          fontFamilyFallback: grid.AppFont.monoFallback,
        ),
      ),
    );
  }
}

/// The same dot the machine rail gives a reachable machine, so one colour keeps
/// meaning one thing across the app.
class _StatusCell extends StatelessWidget {
  const _StatusCell({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final active = status == 'active';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
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
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: grid.AppPalette.textSecondary,
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The chevron that opens a row's drawer.
///
/// Its own hit target inside a row that is itself a button, so it has to stop
/// the tap: `onTap` here must not fall through to the row, or reading a grid's
/// id would move every new agent onto it.
class _DetailsToggle extends StatelessWidget {
  const _DetailsToggle({
    required this.expanded,
    required this.label,
    required this.onPressed,
  });

  final bool expanded;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return AnimatedRotation(
      turns: expanded ? 0.25 : 0,
      duration: grid.AppMotion.hover,
      curve: grid.AppMotion.curve,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(
          LucideIcons.chevronRight300,
          size: 15,
          color: grid.AppPalette.textFaint,
        ),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 26, height: 26),
        // No ripple: the app disables Material's splash everywhere else.
        style: const ButtonStyle(splashFactory: NoSplash.splashFactory),
        hoverColor: grid.AppSurface.hoverFill,
        tooltip: expanded ? 'Hide details for $label' : 'Details for $label',
      ),
    );
  }
}

/// What the card used to print on every grid at once: the id, the signaling
/// URL, the owner, the router's advisors — for the one grid you asked about.
class _DetailDrawer extends StatelessWidget {
  const _DetailDrawer({
    required this.network,
    required this.owned,
    required this.selected,
    required this.last,
  });

  final GridNetwork network;
  final bool owned;
  final bool selected;
  final bool last;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final description = network.description?.trim() ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(_Columns.pickWidth + 12, 12, 14, 14),
      decoration: BoxDecoration(
        color: selected ? grid.AppSurface.accentWash : grid.AppSurface.recess,
        border: last
            ? null
            : Border(bottom: BorderSide(color: grid.AppPalette.divider)),
      ),
      child: Wrap(
        spacing: 32,
        runSpacing: 14,
        children: [
          if (description.isNotEmpty)
            _Pair(label: 'Description', child: _PlainValue(description)),
          _Pair(
            label: 'Grid ID',
            child: _CopyableValue(value: network.networkId),
          ),
          _Pair(
            label: 'Signaling',
            child: network.lanSignalingUrl == null
                ? const _PlainValue('—')
                : _CopyableValue(value: network.lanSignalingUrl!),
          ),
          _Pair(
            label: 'Owner',
            child: _PlainValue(owned ? 'You' : network.ownerEmail),
          ),
          _Pair(
            label: 'Router advisors',
            child: network.routerAdvisors.isEmpty
                ? _PlainValue(
                    network.routerEnabled
                        ? 'On, with no advisors listed'
                        : 'Off — requests go straight to this grid’s providers',
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final advisor in network.routerAdvisors)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            advisor,
                            style: TextStyle(
                              color: grid.AppPalette.textSecondary,
                              fontSize: 11.5,
                              fontFamily: grid.AppFont.mono,
                              fontFamilyFallback: grid.AppFont.monoFallback,
                            ),
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

/// One labelled fact in a drawer. Fixed width so the pairs tile into columns
/// that line up down the pane instead of reflowing to their own contents.
class _Pair extends StatelessWidget {
  const _Pair({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return SizedBox(
      width: 250,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: grid.AppPalette.textFaint,
              fontSize: 10,
              fontWeight: grid.AppFont.semibold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

class _PlainValue extends StatelessWidget {
  const _PlainValue(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Text(
      value,
      style: TextStyle(
        color: grid.AppPalette.textSecondary,
        fontSize: 12,
        height: 1.4,
      ),
    );
  }
}

/// A mono value with a copy affordance that appears under the pointer.
///
/// These are the two strings a person actually needs off this screen — the id
/// goes into `harness link import`, the URL into a browser — and both are long
/// enough that selecting them by hand from a table row is a chore.
class _CopyableValue extends StatefulWidget {
  const _CopyableValue({required this.value});

  final String value;

  @override
  State<_CopyableValue> createState() => _CopyableValueState();
}

class _CopyableValueState extends State<_CopyableValue> {
  bool _hovered = false;
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Row(
        children: [
          Flexible(
            child: Text(
              widget.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: grid.AppPalette.textSecondary,
                fontSize: 11.5,
                fontFamily: grid.AppFont.mono,
                fontFamilyFallback: grid.AppFont.monoFallback,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // The slot is held whether or not the button is drawn, so a value
          // does not jump sideways when the pointer arrives.
          SizedBox(
            width: 22,
            height: 22,
            child: (_hovered || _copied)
                ? IconButton(
                    onPressed: _copy,
                    icon: Icon(
                      _copied ? LucideIcons.check300 : LucideIcons.copy300,
                      size: 13,
                      color: _copied
                          ? grid.AppPalette.online
                          : grid.AppPalette.textFaint,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 22,
                      height: 22,
                    ),
                    style: const ButtonStyle(
                      splashFactory: NoSplash.splashFactory,
                    ),
                    hoverColor: grid.AppSurface.hoverFill,
                    tooltip: _copied ? 'Copied' : 'Copy',
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.value));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (mounted) setState(() => _copied = false);
  }
}

/// A table with no rows under its header — either the account is on no grids,
/// or the filter matched none. Saying which is the whole point: the two look
/// identical and mean opposite things.
class _EmptyRows extends StatelessWidget {
  const _EmptyRows({required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(
          filtered
              ? 'No grid matches that filter.'
              : 'This account is not on a grid yet. Join one from the Grid '
                    'app, then reload here.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: grid.AppPalette.textFaint,
            fontSize: 12.5,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

/// `https://` carries no information in a column this narrow — the scheme is
/// the same on every grid, and dropping it buys back eight characters of the
/// host that is not.
String? _shortUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  for (final scheme in const ['https://', 'http://']) {
    if (url.startsWith(scheme)) return url.substring(scheme.length);
  }
  return url;
}
