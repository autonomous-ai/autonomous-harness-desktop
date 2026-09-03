import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../grid/grid_models_controller.dart';
import '../../grid/grid_selection_store.dart';
import '../../shared/theme/app_theme.dart' as grid;
import '../../widgets/grid_selector_menus.dart';

/// The answer, above the list that changes it: which grid new agents launch
/// against, and on which model.
///
/// The pane had no such line. It listed grids and marked one of them, so
/// "where do my agents run right now" was a question you answered by scanning
/// four cards for a differently-worded pill — and the model, which the sidebar
/// has always let you set, was not on this screen at all.
///
/// It carries the model control rather than putting one on every row, for the
/// reason the sidebar does: a model id only means something on the grid that
/// serves it, so there is only ever one model to choose.
class GridTargetStrip extends StatelessWidget {
  const GridTargetStrip({
    super.key,
    required this.selection,
    required this.chosen,
    this.models,
  });

  final GridSelectionStore selection;
  final GridSelection chosen;

  /// Injected by tests. The app uses the shared instance, so the sidebar's
  /// model menu and this one never hold two different lists for one grid.
  final GridModelsController? models;

  GridModelsController get _models => models ?? gridModelsController;

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
            child: Wrap(
              spacing: 28,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _Readout(
                  label: 'New agents use',
                  value: on ? chosen.label : "Each engine's own login",
                  muted: !on,
                ),
                _Readout(
                  label: 'Model',
                  // An em dash rather than "Auto" with no grid: Auto is a
                  // choice the relay makes, and with no relay in the picture
                  // there is nothing to make it.
                  value: on ? (chosen.model ?? 'Auto') : '—',
                  muted: !on || chosen.model == null,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // No grid, no model menu — the sidebar hides the same control for
          // the same reason rather than showing one that can only say "Auto".
          if (on)
            ModelMenu(
              selection: selection,
              models: _models,
              chosen: chosen,
              child: (open) => _ModelTrigger(
                key: const Key('grid-model-trigger'),
                // Spelled out rather than the bare word: "Auto" alone reads as
                // a model id, and the one thing a reader needs to know is that
                // nobody has pinned one.
                label: chosen.model ?? 'Auto — the grid decides',
                muted: chosen.model == null,
                onTap: open,
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

/// The control the model menu hangs off.
///
/// Shaped like [AppSelectField]'s closed field — the app's one recessed well
/// with a label and a chevron — but driven by [ModelMenu], which loads the
/// grid's models only when the menu opens. A real select field would have to
/// be handed the list up front, and building this pane would then fire two
/// control-plane calls at anyone who merely walked past Settings ▸ Grid.
class _ModelTrigger extends StatefulWidget {
  const _ModelTrigger({
    super.key,
    required this.label,
    required this.muted,
    required this.onTap,
  });

  final String label;
  final bool muted;
  final VoidCallback onTap;

  @override
  State<_ModelTrigger> createState() => _ModelTriggerState();
}

class _ModelTriggerState extends State<_ModelTrigger> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: grid.AppMotion.hover,
          curve: grid.AppMotion.curve,
          width: 214,
          height: grid.AppControl.height,
          padding: const EdgeInsets.only(left: 12, right: 8),
          decoration: BoxDecoration(
            color: _hovered
                ? grid.AppGlass.surfaceHoverFill
                : grid.AppGlass.surfaceFill,
            borderRadius: BorderRadius.circular(grid.AppControl.radius),
            // Rimmed in the accent, not the usual hairline: it is the only
            // control on a strip that is already washed in accent, and a
            // hairline disappears into that wash.
            border: Border.all(
              color: grid.AppPalette.accent.withValues(alpha: 0.55),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.muted
                        ? grid.AppPalette.textSecondary
                        : grid.AppPalette.textPrimary,
                    fontSize: grid.AppControl.fontSize,
                    fontWeight: grid.AppControl.fontWeight,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                LucideIcons.chevronDown300,
                size: 14,
                color: _hovered
                    ? grid.AppPalette.textPrimary
                    : grid.AppPalette.textFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
