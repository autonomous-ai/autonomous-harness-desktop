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
  });

  final GridNetwork network;

  /// Whose session this is, so the card can say "you own this" rather than
  /// printing an email the reader has to compare against their own.
  final String signedInEmail;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final owned = network.isOwnedBy(signedInEmail);
    final roles = network.member?.roles ?? const <String>[];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      decoration: BoxDecoration(
        color: grid.AppGlass.surfaceFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: grid.AppGlass.hair),
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
              if (owned) const _Pill(label: 'You own this', accent: true),
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

/// A word about this grid, in a quiet capsule.
class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.accent = false});

  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: accent
            ? grid.AppSurface.accentWash
            : grid.AppSurface.selectedFill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accent
              ? grid.AppPalette.accentOnSurface
              : grid.AppPalette.textSecondary,
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
