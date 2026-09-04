import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../grid/grid_selection_store.dart';
import '../../shared/theme/app_theme.dart' as grid;

/// The answer, above the list that changes it: which grid new agents launch
/// against.
///
/// The pane had no such line. It listed grids and marked one of them, so
/// "where do my agents run right now" was a question you answered by scanning
/// four cards for a differently-worded pill.
class GridTargetStrip extends StatelessWidget {
  const GridTargetStrip({super.key, required this.chosen});

  final GridSelection chosen;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final on = chosen.hasGrid;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: on ? grid.AppSurface.accentWash : grid.AppSurface.recess,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: on
              ? grid.AppPalette.accent.withValues(alpha: 0.26)
              : grid.AppGlass.hair,
        ),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.zap300,
            size: 20,
            color: on
                ? grid.AppPalette.accentOnSurface
                : grid.AppPalette.textFaint,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _Readout(
              label: 'New agents use',
              value: on ? chosen.label : "Each engine's own login",
              muted: !on,
            ),
          ),
        ],
      ),
    );
  }
}

/// One `LABEL / value` pair in the strip.
class _Readout extends StatelessWidget {
  const _Readout({
    required this.label,
    required this.value,
    required this.muted,
  });

  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Column(
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
        const SizedBox(height: 3),
        ConstrainedBox(
          // Wide enough for a grid name, short enough that two readouts and a
          // control still fit the pane at its narrowest.
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: muted
                  ? grid.AppPalette.textSecondary
                  : grid.AppPalette.textPrimary,
              fontSize: 14,
              fontWeight: muted ? grid.AppFont.regular : grid.AppFont.semibold,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ],
    );
  }
}
