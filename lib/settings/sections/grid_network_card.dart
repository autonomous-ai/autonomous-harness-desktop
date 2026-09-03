import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../grid/grid_network.dart';
import '../../shared/theme/app_theme.dart' as grid;

/// One grid, as a card: what it is called, what this account may do on it, and
/// the handful of facts that identify it.
///
/// A card per grid rather than a table: the rows are not comparable column by
/// column — a grid you own and a grid you consume on differ in which fields
/// even apply — and a settings pane is too narrow to hold nine columns anyway.
class GridNetworkCard extends StatelessWidget {
  const GridNetworkCard({
    super.key,
    required this.network,
    required this.signedInEmail,
    this.selected = false,
    this.onToggle,
  });

  final GridNetwork network;

  /// Whose session this is, so the card can say "you own this" rather than
  /// printing an email the reader has to compare against their own.
  final String signedInEmail;

  /// This is the grid new agents are launched against.
  final bool selected;

  /// Turn this grid on, or — when it is already on — off again.
  ///
  /// One callback for both directions because it is one control: a choice you
  /// can make and a choice you cannot unmake is a trap, and the way out used to
  /// be a row in a different menu ("Each engine's own login") that nobody would
  /// think to look for from here.
  ///
  /// Null hides the action entirely — a card that offered it with nowhere to
  /// record it would lie.
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final owned = network.isOwnedBy(signedInEmail);
    final roles = network.member?.roles ?? const <String>[];
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      decoration: BoxDecoration(
        color: selected
            ? grid.AppSurface.accentWash
            : grid.AppGlass.surfaceFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected
              ? grid.AppPalette.accentOnSurface
              : grid.AppGlass.hair,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  network.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: grid.AppPalette.textPrimary,
                    fontSize: 13.5,
                    fontWeight: grid.AppFont.semibold,
                  ),
                ),
              ),
              // Status lives beside the name because it is the one fact that
              // decides whether anything below it matters.
              _StatusDot(status: network.status),
              if (onToggle != null) ...[
                const SizedBox(width: 12),
                _UseToggle(selected: selected, onPressed: onToggle!),
              ],
            ],
          ),
          if (network.description?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 4),
            Text(
              network.description!.trim(),
              style: TextStyle(
                color: grid.AppPalette.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 9),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (owned) const _Pill(label: 'You own this'),
              for (final role in roles) _Pill(label: role),
              _Pill(label: network.networkType),
              if (network.routerEnabled)
                _Pill(
                  label: network.routerAdvisors.isEmpty
                      ? 'router on'
                      : 'router · ${network.routerAdvisors.join(', ')}',
                ),
              if (network.accessDomain != null)
                _Pill(label: '@${network.accessDomain}'),
            ],
          ),
          const SizedBox(height: 10),
          _MetaRow(icon: LucideIcons.hash300, value: network.networkId),
          if (!owned)
            _MetaRow(icon: LucideIcons.user300, value: network.ownerEmail),
          if (network.lanSignalingUrl != null)
            _MetaRow(
              icon: LucideIcons.link300,
              value: network.lanSignalingUrl!,
            ),
        ],
      ),
    );
  }
}

/// Use this grid for new agents — and stop using it.
///
/// A real button rather than the text link this used to be. It was 28px tall
/// and eight pixels of padding wide, which is under every target size Apple and
/// WCAG ask for, and once a grid was chosen it stopped being a control at all:
/// the state replaced the action, so the only way back was a row in the
/// sidebar's menu. Pressing it again is now the way out, and the label says so
/// on hover rather than making somebody discover it by pressing.
class _UseToggle extends StatefulWidget {
  const _UseToggle({required this.selected, required this.onPressed});

  final bool selected;
  final VoidCallback onPressed;

  @override
  State<_UseToggle> createState() => _UseToggleState();
}

class _UseToggleState extends State<_UseToggle> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    // On a chosen grid the button's job changes to "stop", and saying so only
    // under the pointer keeps the resting state readable as a state.
    final leaving = widget.selected && _hovering;
    final label = switch ((widget.selected, leaving)) {
      (true, true) => 'Stop using',
      (true, false) => 'In use',
      _ => 'Use for new agents',
    };
    final ink = leaving
        ? grid.AppPalette.dangerFill
        : widget.selected
        ? grid.AppPalette.accentOnSurface
        : grid.AppPalette.textSecondary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: widget.selected
                ? grid.AppGlass.surfaceFill
                : grid.AppSurface.selectedFill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: leaving
                  ? grid.AppPalette.dangerFill
                  : widget.selected
                  ? grid.AppPalette.accentOnSurface
                  : grid.AppGlass.hair,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                leaving
                    ? LucideIcons.x300
                    : widget.selected
                    ? LucideIcons.check300
                    : LucideIcons.plus300,
                size: 14,
                color: ink,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: ink,
                  fontSize: 12,
                  fontWeight: grid.AppFont.semibold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A word about this grid, in a quiet capsule.
///
/// One tone only. There used to be an accent variant, worn by "You own this"
/// and by the chosen-grid capsule at once — so on the grid you owned AND used,
/// the fact and the choice were the same colour on the same row, and neither
/// read as either. The choice is a button now, and accent belongs to it.
class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: grid.AppSurface.selectedFill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: grid.AppPalette.textSecondary,
          fontSize: 10.5,
          fontWeight: grid.AppFont.medium,
        ),
      ),
    );
  }
}

/// Green while the grid is active, muted otherwise — the same mark the machine
/// rail uses for a reachable machine, so one colour means one thing.
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

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
            color: active ? grid.AppPalette.online : grid.AppPalette.offline,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          status,
          style: TextStyle(color: grid.AppPalette.textFaint, fontSize: 11),
        ),
      ],
    );
  }
}

/// One `glyph value` line of small print under a card's badges.
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(icon, size: 13, color: grid.AppPalette.textFaint),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: grid.AppPalette.textFaint,
                fontSize: 11.5,
                fontFamily: grid.AppFont.mono,
                fontFamilyFallback: grid.AppFont.monoFallback,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
