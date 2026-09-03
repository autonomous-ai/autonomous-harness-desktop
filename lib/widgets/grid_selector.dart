import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../grid/grid_models_controller.dart';
import '../grid/grid_networks_controller.dart';
import '../grid/grid_selection_store.dart';
import '../shared/layouts/widgets/rail_section_header.dart';
import '../shared/theme/app_theme.dart' as grid;
import 'grid_selector_menus.dart';

/// The grid and model a NEW agent will be launched against.
///
/// It sits at the foot of the sidebar, above the account, because that is where
/// this app already keeps the things that are true of the whole window rather
/// than of one machine — and because the choice has to be visible while you are
/// looking at the machine you are about to add an agent to.
///
/// The caption is the whole design. "New agents use" is the honest sentence:
/// choosing here retargets nothing that is already running, and a control
/// labelled just "Grid" would have implied it did.
class GridSelector extends StatelessWidget {
  const GridSelector({
    super.key,
    this.compact = false,
    this.selection,
    this.networks,
    this.models,
  });

  /// The folded rail: one glyph, same menus.
  final bool compact;

  /// Injected by tests. The app uses the shared instances, which is what lets
  /// Settings and this control change the same choice.
  final GridSelectionStore? selection;
  final GridNetworksController? networks;
  final GridModelsController? models;

  GridSelectionStore get _selection => selection ?? gridSelectionStore;
  GridNetworksController get _networks => networks ?? gridNetworksController;
  GridModelsController get _models => models ?? gridModelsController;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return ValueListenableBuilder<GridSelection>(
      valueListenable: _selection,
      builder: (context, chosen, _) {
        if (compact) {
          return GridMenu(
            selection: _selection,
            networks: _networks,
            chosen: chosen,
            child: (open) => IconButton(
              tooltip: chosen.hasGrid
                  ? 'New agents use ${chosen.label}'
                  : 'Pick a grid for new agents',
              onPressed: open,
              icon: Icon(
                LucideIcons.zap300,
                size: 18,
                color: chosen.hasGrid
                    ? grid.AppPalette.accentOnSurface
                    : grid.AppPalette.textFaint,
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const RailSectionHeader(label: 'New agents use'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  children: [
                    GridMenu(
                      selection: _selection,
                      networks: _networks,
                      chosen: chosen,
                      child: (open) => _PickerRow(
                        key: const Key('grid-picker-row'),
                        icon: LucideIcons.zap300,
                        label: chosen.hasGrid
                            ? chosen.label
                            : "Each engine's own login",
                        muted: !chosen.hasGrid,
                        onTap: open,
                      ),
                    ),
                    // No grid, no model: a model id only means something on the
                    // grid that serves it.
                    if (chosen.hasGrid) ...[
                      const SizedBox(height: 4),
                      ModelMenu(
                        selection: _selection,
                        models: _models,
                        chosen: chosen,
                        child: (open) => _PickerRow(
                          key: const Key('grid-model-row'),
                          icon: LucideIcons.boxes300,
                          label: chosen.model ?? 'Auto',
                          muted: chosen.model == null,
                          onTap: open,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The button the menus hang off: a glyph, the current value, a chevron.
class _PickerRow extends StatelessWidget {
  const _PickerRow({
    super.key,
    required this.icon,
    required this.label,
    required this.muted,
    required this.onTap,
  });

  final IconData icon;
  final String label;

  /// Drawn quieter when the value is a default rather than a choice.
  final bool muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Material(
      color: grid.AppSurface.recess,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(9, 6, 6, 6),
          child: Row(
            children: [
              Icon(
                icon,
                size: 14,
                color: muted
                    ? grid.AppPalette.textFaint
                    : grid.AppPalette.accentOnSurface,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: muted
                        ? grid.AppPalette.textFaint
                        : grid.AppPalette.textPrimary,
                    fontSize: 12.5,
                  ),
                ),
              ),
              Icon(
                LucideIcons.chevronsUpDown300,
                size: 13,
                color: grid.AppPalette.textFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
