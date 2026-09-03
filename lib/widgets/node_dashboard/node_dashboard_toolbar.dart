import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../grid/grid_overview.dart';
import '../../grid/node_dashboard_view.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/app_menu.dart';
import '../../shared/widgets/toolbar_pill.dart';

/// The strip above the node cards: what they are ordered by, and which of them
/// are shown.
///
/// Ported from Grid (`features/network/presentation/node_dashboard_toolbar.dart`),
/// with its `MenuRow` swapped for this app's [AppMenuItem] — one menu row for
/// the app, rather than a second one that would drift from the pickers already
/// in Settings.
///
/// Three menus rather than a row of pills per value, because each answers a
/// single question with one answer in force at a time, and a grid can serve a
/// dozen models — a pill each would be a paragraph of controls above a dashboard
/// they are only there to point at.
///
/// **Given every online node, not the filtered ones.** The menus list what the
/// grid has, so narrowing to one model must not shrink the model menu to that
/// model — that is a filter you can enter and never leave.
class NodeDashboardToolbar extends StatelessWidget {
  const NodeDashboardToolbar({
    super.key,
    required this.nodes,
    required this.store,
  });

  final List<OverviewNode> nodes;
  final NodeDashboardViewStore store;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final view = store.value;
    final models = nodeDashboardModels(nodes);
    final platforms = nodeDashboardPlatforms(nodes);

    // `Wrap`, so a narrow window drops a control to a second line instead of
    // overflowing the dialog — the app runs in a resizable desktop window.
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _PickerPill<NodeSortKey>(
          icon: LucideIcons.arrowDownWideNarrow,
          label: nodeSortLabel(view.sort),
          value: view.sort,
          // Wider than the filter menus because these rows carry a second line,
          // which ellipsizes: at 268 "Most tokens generated in the last 24h"
          // lost its last word, and that word is the one saying the figure is
          // not all-time.
          width: 300,
          options: [
            for (final key in NodeSortKey.values)
              (
                value: key,
                label: nodeSortLabel(key),
                detail: nodeSortDetail(key),
              ),
          ],
          onPick: store.sortBy,
        ),
        // A menu that can only re-pick what is already in force narrows nothing,
        // so a grid serving one model is offered no model filter. The clear
        // button below is what keeps that from stranding anybody: a filter set
        // while the grid had more can always be undone, even after the machine
        // behind it went offline and took its menu row with it.
        if (models.length > 1)
          _PickerPill<String?>(
            icon: LucideIcons.boxes,
            label: view.model == null
                ? 'All models'
                : modelLabelForKey(models, view.model!),
            value: view.model,
            options: [
              (value: null, label: 'All models', detail: null),
              for (final id in models)
                (value: id, label: modelLabel(id), detail: null),
            ],
            onPick: store.showModel,
          ),
        if (platforms.length > 1)
          _PickerPill<String?>(
            icon: LucideIcons.monitor,
            label: view.platform ?? 'All platforms',
            value: view.platform,
            options: [
              (value: null, label: 'All platforms', detail: null),
              for (final label in platforms)
                (value: label, label: label, detail: null),
            ],
            onPick: store.showPlatform,
          ),
        if (view.isFiltered)
          ToolbarPill(
            onTap: store.clearFilters,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.x, size: 13, color: AppPalette.textSecondary),
                const SizedBox(width: 5),
                Text(
                  'Show all',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: AppFont.medium,
                    color: AppPalette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One option in a [_PickerPill] — its value, what to call it, and an optional
/// second line saying what picking it does.
typedef _Option<T> = ({T value, String label, String? detail});

/// A toolbar control: a pill saying what is in force, and the menu of what else
/// there is.
///
/// One widget for all three because they differ only in their options — three
/// hand-built [MenuAnchor]s beside each other is how a toolbar ends up with two
/// carets of different sizes and one menu that opens 2px further from its
/// button.
class _PickerPill<T> extends StatefulWidget {
  const _PickerPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.options,
    required this.onPick,
    this.width = 236,
  });

  /// The glyph before the label — what the control is *about*, so the pills stay
  /// tellable apart when their labels are all short words.
  final IconData icon;

  /// What the pill prints: the option in force, not the question it answers. The
  /// question is the glyph's job; the row has no width to spend on "Sort by".
  final String label;

  final T value;
  final List<_Option<T>> options;
  final ValueChanged<T> onPick;

  /// How wide the menu draws. Its rows ellipsize inside it, so this is what
  /// decides whether a long model id survives.
  final double width;

  @override
  State<_PickerPill<T>> createState() => _PickerPillState<T>();
}

class _PickerPillState<T> extends State<_PickerPill<T>> {
  final _menu = MenuController();

  /// What this menu's rows come to, laid out.
  ///
  /// [AppMenuRowMetrics] states both extents rather than deriving them, because
  /// a line box rounds up to the font's own metrics: adding the paddings gives
  /// 33.6 where a row measures 34, and over six rows that is enough to hang a
  /// scrollbar on a panel sized by the arithmetic.
  double get _panelHeight {
    const metrics = AppMenuRowMetrics.compact;
    final tall = widget.options.any((option) => option.detail != null);
    final extent = tall ? metrics.detailExtent : metrics.extent;
    return widget.options.length * extent + AppMenu.panelPadding.vertical;
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return MenuAnchor(
      controller: _menu,
      alignmentOffset: const Offset(0, 6),
      style: AppMenu.style(
        minWidth: widget.width,
        maxWidth: widget.width,
        // Sized from the rows rather than left on [AppControl.menuMaxHeight].
        // That cap is 240 and suits a CONTEXT menu, where a short list is the
        // norm; this is a picker's list, and the sort menu's six rows each
        // carry a second line — 310px of them, which the cap would scroll,
        // putting the last two orders below a fold nobody expects in a
        // six-item menu. Beyond the screen the layout clamps and scrolls on
        // its own, which is what a menu of thirty models should do.
        maxHeight: _panelHeight,
      ),
      menuChildren: [
        for (final option in widget.options)
          AppMenuItem(
            label: option.label,
            detail: option.detail,
            selected: option.value == widget.value,
            onPressed: () {
              _menu.close();
              widget.onPick(option.value);
            },
          ),
      ],
      builder: (context, controller, _) => _PillButton(
        icon: widget.icon,
        label: widget.label,
        controller: controller,
      ),
    );
  }
}

/// The pill itself: glyph, the option in force, and a caret that turns over when
/// the menu is open.
class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.controller,
  });

  final IconData icon;
  final String label;
  final MenuController controller;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final open = controller.isOpen;
    return ToolbarPill(
      active: open,
      onTap: () => open ? controller.close() : controller.open(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppPalette.textSecondary),
          const SizedBox(width: 6),
          // Capped rather than free: a model id can run to forty characters, and
          // an uncapped pill would push the controls beside it off the dialog.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: AppFont.medium,
                color: AppPalette.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          AnimatedRotation(
            duration: AppMotion.hover,
            curve: AppMotion.curve,
            turns: open ? 0.5 : 0,
            child: Icon(
              LucideIcons.chevronDown,
              size: 13,
              color: AppPalette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
