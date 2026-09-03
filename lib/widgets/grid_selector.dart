import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../grid/grid_models_controller.dart';
import '../grid/grid_networks_controller.dart';
import '../grid/grid_selection_store.dart';
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
///
/// ### Why it is one card and not two rows
///
/// The two pickers used to be two full-width blocks the same height and the
/// same shape as an agent row, stacked directly under the list. At a glance the
/// rail read as: three agents, then two more agents called "Water Grid" and
/// "Auto". Recessing both into a single card under one caption says what they
/// actually are — one setting with two parts, belonging to the button at the
/// top of the rail rather than to the list above them.
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
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: grid.AppSurface.recess,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 1, bottom: 5),
                    child: Text(
                      'New agents use',
                      style: TextStyle(
                        color: grid.AppPalette.textFaint,
                        fontFamily: grid.AppFont.sans,
                        fontSize: 10.5,
                        fontWeight: grid.AppFont.semibold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  GridMenu(
                    selection: _selection,
                    networks: _networks,
                    chosen: chosen,
                    child: (open) => _TargetRow(
                      key: const Key('grid-picker-row'),
                      name: 'Grid',
                      value: chosen.hasGrid
                          ? chosen.label
                          : "Each engine's own login",
                      icon: LucideIcons.zap300,
                      muted: !chosen.hasGrid,
                      onTap: open,
                    ),
                  ),
                  // No grid, no model: a model id only means something on the
                  // grid that serves it.
                  if (chosen.hasGrid)
                    ModelMenu(
                      selection: _selection,
                      models: _models,
                      chosen: chosen,
                      child: (open) => _TargetRow(
                        key: const Key('grid-model-row'),
                        name: 'Model',
                        value: chosen.model ?? 'Auto',
                        muted: chosen.model == null,
                        onTap: open,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One half of the launch target: what it is on the left, what it is set to on
/// the right.
///
/// The name column is what makes this a settings block rather than a list. Two
/// unlabelled values stacked ("Water Grid" over "Auto") leave the second one
/// unreadable — "Auto" what? — and that ambiguity is exactly what put a glyph
/// on the model row purely to fill the space a label should have held.
class _TargetRow extends StatefulWidget {
  const _TargetRow({
    super.key,
    required this.name,
    required this.value,
    required this.muted,
    required this.onTap,
    this.icon,
  });

  final String name;
  final String value;

  /// Drawn on the value only when the choice IS one — the grid's bolt. The
  /// model row has no mark, because a mark that means nothing is decoration.
  final IconData? icon;

  /// Drawn quieter when the value is a default rather than a choice.
  final bool muted;
  final VoidCallback onTap;

  /// The width the names line up in. Both fit inside it at this size, so the
  /// two values start on one edge and the pair reads as a column.
  static const double _nameWidth = 42;

  @override
  State<_TargetRow> createState() => _TargetRowState();
}

class _TargetRowState extends State<_TargetRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: grid.AppMotion.hover,
          curve: grid.AppMotion.curve,
          height: 26,
          // The hover pill runs a little wider than the text so it reads as the
          // row lifting, not as a box drawn around the value.
          padding: const EdgeInsets.symmetric(horizontal: 5),
          margin: const EdgeInsets.symmetric(vertical: 1),
          decoration: BoxDecoration(
            color: _hovered ? grid.AppSurface.hoverFill : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            children: [
              SizedBox(
                width: _TargetRow._nameWidth,
                child: Text(
                  widget.name,
                  style: TextStyle(
                    color: grid.AppPalette.textFaint,
                    fontFamily: grid.AppFont.sans,
                    fontSize: 12,
                  ),
                ),
              ),
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  size: 13,
                  color: widget.muted
                      ? grid.AppPalette.textFaint
                      : grid.AppPalette.accentOnSurface,
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  widget.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.muted
                        ? grid.AppPalette.textSecondary
                        : grid.AppPalette.textPrimary,
                    fontFamily: grid.AppFont.sans,
                    fontSize: 12.5,
                    fontWeight: widget.muted
                        ? FontWeight.w400
                        : grid.AppFont.medium,
                  ),
                ),
              ),
              const SizedBox(width: 4),
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
