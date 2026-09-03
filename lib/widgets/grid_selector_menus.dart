import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../grid/grid_models_controller.dart';
import '../grid/grid_networks_controller.dart';
import '../grid/grid_selection_store.dart';
import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/app_menu.dart';

/// The two grid pickers' panels.
///
/// Both are **pickers**, not context menus: the panel IS the control, it is the
/// only place these choices are ever shown, and a model list is read down rather
/// than glanced at — so the rows take [AppMenuRowMetrics.roomy], the same size
/// [AppSelectField] gives its list.
///
/// These used to be bare [MenuItemButton]s under a hand-written `MenuStyle`,
/// which is the drift `app_menu.dart` was written to end: Material's M3 defaults
/// gave them square hover, 14pt text, a grey 8% wash and a ripple every other
/// menu in the app has turned off, and the panel had its own fill, rim, radius
/// and elevation numbers that agreed with nothing.

/// The width every row is laid out at, and therefore the panel's.
///
/// ⚠️ Set on the ROWS, not with `MenuStyle.minimumSize` — see the note in
/// [AppSelectField]: `MenuAnchor` lays its children out loose, so `minimumSize`
/// widens the panel while the rows keep their intrinsic width, and the hover
/// pill then stops short of the edge a person is aiming at.
///
/// Wider than either trigger (the strip's model field is 214, the rail's picker
/// rows about 240), because the panel has to hold a model id like
/// `DeepSeek-V4-Flash-0731` that neither trigger ever shows in full.
const double _kPanelWidth = 284;

/// What the panel may grow to before it scrolls.
///
/// NOT [grid.AppControl.menuMaxHeight]: that 240 is for a menu that opens
/// upward and has to place itself by summing its own height. These hang below
/// their control, so the cap only decides when a long list starts scrolling —
/// and at 240 a grid serving seven models scrolled for no reason.
const double _kMaxPanelHeight = 380;

/// The grids menu: every grid this account is on, plus the way back out.
class GridMenu extends StatefulWidget {
  const GridMenu({
    super.key,
    required this.selection,
    required this.networks,
    required this.chosen,
    required this.child,
  });

  final GridSelectionStore selection;
  final GridNetworksController networks;
  final GridSelection chosen;
  final Widget Function(VoidCallback open) child;

  @override
  State<GridMenu> createState() => _GridMenuState();
}

class _GridMenuState extends State<GridMenu> {
  // ⚠️ Held, and closed by every row. [AppMenuItem] is a hand-rolled InkWell
  // rather than a [MenuItemButton] — the reason is in its own doc — and an
  // InkWell does not dismiss the panel it sits in. Without this the menu stayed
  // open over the control after a pick, swallowing the next click.
  final _controller = MenuController();

  GridSelectionStore get selection => widget.selection;
  GridNetworksController get networks => widget.networks;
  GridSelection get chosen => widget.chosen;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: networks,
      builder: (context, _) {
        final panel = _Panel(_controller)
          ..row(
            label: "Each engine's own login",
            selected: !chosen.hasGrid,
            onPressed: () => unawaited(selection.clear()),
          )
          ..divider();
        _appendGrids(panel);
        return _anchor(
          controller: _controller,
          panel: panel,
          // Lazy: nothing is fetched until someone asks to choose.
          onOpen: networks.ensureLoaded,
          child: widget.child,
        );
      },
    );
  }

  void _appendGrids(_Panel panel) {
    switch (networks.state) {
      case GridNetworksIdle():
      case GridNetworksLoading():
        panel.note('Loading your grids…');
      case GridNetworksFailed(:final message):
        panel.note(message);
      case GridNetworksReady(:final me):
        if (me.networks.isEmpty) {
          panel.note('This account is not on a grid yet.');
          return;
        }
        for (final network in me.networks) {
          panel.row(
            label: network.displayName,
            selected: network.networkId == chosen.networkId,
            onPressed: () => unawaited(
              selection.selectNetwork(
                networkId: network.networkId,
                networkName: network.displayName,
              ),
            ),
          );
        }
    }
  }
}

/// The models menu for the chosen grid.
class ModelMenu extends StatefulWidget {
  const ModelMenu({
    super.key,
    required this.selection,
    required this.models,
    required this.chosen,
    required this.child,
  });

  final GridSelectionStore selection;
  final GridModelsController models;
  final GridSelection chosen;
  final Widget Function(VoidCallback open) child;

  @override
  State<ModelMenu> createState() => _ModelMenuState();
}

class _ModelMenuState extends State<ModelMenu> {
  final _controller = MenuController();

  GridSelectionStore get selection => widget.selection;
  GridModelsController get models => widget.models;
  GridSelection get chosen => widget.chosen;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: models,
      builder: (context, _) {
        final panel = _Panel(_controller)
          ..row(
            // Spelled out, and NOT the bare word "Auto": a grid whose router is
            // on serves a pseudo-model literally called `Auto`, so this row and
            // a row in the list below it read as the same thing while meaning
            // two different ones — pin nothing and let the relay choose, versus
            // pin the id `Auto`.
            label: 'Auto — the grid decides',
            selected: chosen.model == null,
            onPressed: () => unawaited(selection.selectModel(null)),
          )
          ..divider();
        _appendModels(panel);
        return _anchor(
          controller: _controller,
          panel: panel,
          onOpen: () => models.ensureLoadedFor(chosen.networkId!),
          child: widget.child,
        );
      },
    );
  }

  void _appendModels(_Panel panel) {
    switch (models.state) {
      case GridModelsIdle():
      case GridModelsLoading():
        panel.note('Loading models…');
      case GridModelsFailed(:final message):
        panel.note(message);
      case GridModelsReady(:final models):
        if (models.isEmpty) {
          panel.note('This grid serves no models right now.');
          return;
        }
        for (final model in models) {
          panel.row(
            label: model,
            selected: model == chosen.model,
            onPressed: () => unawaited(selection.selectModel(model)),
          );
        }
    }
  }
}

Widget _anchor({
  required MenuController controller,
  required _Panel panel,
  required VoidCallback onOpen,
  required Widget Function(VoidCallback open) child,
}) {
  return MenuAnchor(
    controller: controller,
    // Below the control, by the app's one menu gap; fill, rim, radius and lift
    // all come from [AppMenu], the app's single panel recipe.
    alignmentOffset: const Offset(0, grid.AppControl.menuGap),
    style: grid.AppMenu.style(maxHeight: panel.height),
    onOpen: onOpen,
    menuChildren: panel.children,
    builder: (context, controller, _) =>
        child(controller.isOpen ? controller.close : controller.open),
  );
}

/// The rows of one panel, and the height they add up to.
///
/// The height is carried rather than left to the cap because a panel is capped,
/// not sized: it shrink-wraps its rows and grows a scrollbar only past the
/// ceiling. Summed here, a seven-model grid opens at seven rows tall with no
/// scrollbar, and only a genuinely long list gets one.
class _Panel {
  _Panel(this._controller);

  final MenuController _controller;
  final children = <Widget>[];
  double _extent = grid.AppMenu.panelPadding.vertical;

  double get height => math.min(_extent, _kMaxPanelHeight);

  void row({
    required String label,
    required bool selected,
    required VoidCallback onPressed,
  }) {
    children.add(
      SizedBox(
        width: _kPanelWidth,
        child: AppMenuItem(
          // A picker's row, not a context menu's.
          metrics: AppMenuRowMetrics.roomy,
          // No glyph of its own: the leading slot belongs to the tick, and
          // `selected` also carries the accent wash and the heavier label, so
          // the choice is marked three ways rather than by a tick alone.
          selected: selected,
          label: label,
          onPressed: () {
            _controller.close();
            onPressed();
          },
        ),
      ),
    );
    _extent += AppMenuRowMetrics.roomy.extent;
  }

  void divider() {
    children.add(const AppMenuDivider());
    _extent += _kDividerExtent;
  }

  /// A line of small print in place of rows — loading, empty, or failed.
  void note(String message) {
    children.add(_MenuNote(message));
    _extent += _kNoteExtent;
  }

  // 1px rule inside AppMenuDivider's 5px vertical padding.
  static const double _kDividerExtent = 11;

  // Two lines of 12pt with the note's own padding. A failure long enough to run
  // to three gets a scrollbar, which is the right furniture for that case.
  static const double _kNoteExtent = 46;
}

class _MenuNote extends StatelessWidget {
  const _MenuNote(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    // Lives in the MenuAnchor's overlay, so it watches for itself.
    grid.AppTheme.watch(context);
    return SizedBox(
      width: _kPanelWidth,
      child: Padding(
        // The horizontal gutter a row's hover pill leaves, plus that row's own
        // padding — so this line starts on the same column the labels do.
        padding: const EdgeInsets.fromLTRB(17, 7, 17, 7),
        child: Text(
          message,
          style: TextStyle(
            color: grid.AppPalette.textFaint,
            fontFamily: grid.AppFont.sans,
            fontFamilyFallback: grid.AppFont.sansFallback,
            fontSize: AppMenuRowMetrics.roomy.noteSize,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}
