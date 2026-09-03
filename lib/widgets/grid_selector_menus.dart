import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../grid/grid_models_controller.dart';
import '../grid/grid_networks_controller.dart';
import '../grid/grid_selection_store.dart';
import '../shared/theme/app_theme.dart' as grid;

/// The grids menu: every grid this account is on, plus the way back out.
class GridMenu extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: networks,
      builder: (context, _) => MenuAnchor(
        style: _menuStyle(),
        // Lazy: nothing is fetched until someone asks to choose.
        onOpen: networks.ensureLoaded,
        menuChildren: [
          _MenuRow(
            label: "Each engine's own login",
            selected: !chosen.hasGrid,
            onPressed: () => unawaited(selection.clear()),
          ),
          const Divider(height: 9),
          ..._gridRows(),
        ],
        builder: (context, controller, _) =>
            child(controller.isOpen ? controller.close : controller.open),
      ),
    );
  }

  List<Widget> _gridRows() => switch (networks.state) {
    GridNetworksIdle() ||
    GridNetworksLoading() => const [_MenuNote('Loading your grids…')],
    GridNetworksFailed(:final message) => [_MenuNote(message)],
    GridNetworksReady(:final me) =>
      me.networks.isEmpty
          ? const [_MenuNote('This account is not on a grid yet.')]
          : [
              for (final network in me.networks)
                _MenuRow(
                  label: network.displayName,
                  selected: network.networkId == chosen.networkId,
                  onPressed: () => unawaited(
                    selection.selectNetwork(
                      networkId: network.networkId,
                      networkName: network.displayName,
                    ),
                  ),
                ),
            ],
  };
}

/// The models menu for the chosen grid.
class ModelMenu extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: models,
      builder: (context, _) => MenuAnchor(
        style: _menuStyle(),
        onOpen: () => models.ensureLoadedFor(chosen.networkId!),
        menuChildren: [
          _MenuRow(
            label: 'Auto',
            selected: chosen.model == null,
            onPressed: () => unawaited(selection.selectModel(null)),
          ),
          const Divider(height: 9),
          ..._modelRows(),
        ],
        builder: (context, controller, _) =>
            child(controller.isOpen ? controller.close : controller.open),
      ),
    );
  }

  List<Widget> _modelRows() => switch (models.state) {
    GridModelsIdle() ||
    GridModelsLoading() => const [_MenuNote('Loading models…')],
    GridModelsFailed(:final message) => [_MenuNote(message)],
    GridModelsReady(:final models) =>
      models.isEmpty
          ? const [_MenuNote('This grid serves no models right now.')]
          : [
              for (final model in models)
                _MenuRow(
                  label: model,
                  selected: model == chosen.model,
                  onPressed: () => unawaited(selection.selectModel(model)),
                ),
            ],
  };
}

MenuStyle _menuStyle() => MenuStyle(
  backgroundColor: WidgetStatePropertyAll(grid.AppPalette.cardBg),
  surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
  elevation: const WidgetStatePropertyAll(18),
  padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
  minimumSize: const WidgetStatePropertyAll(Size(240, 0)),
  maximumSize: const WidgetStatePropertyAll(Size(320, 420)),
  side: WidgetStatePropertyAll(BorderSide(color: grid.AppGlass.hair)),
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  ),
);

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return MenuItemButton(
      onPressed: onPressed,
      leadingIcon: Icon(
        LucideIcons.check300,
        size: 15,
        // Reserved whether or not it is drawn, so picking a row does not shift
        // every label in the menu sideways.
        color: selected ? grid.AppPalette.accentOnSurface : Colors.transparent,
      ),
      child: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }
}

/// A line of small print in place of rows — loading, empty, or failed.
class _MenuNote extends StatelessWidget {
  const _MenuNote(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: SizedBox(
        width: 210,
        child: Text(
          message,
          style: TextStyle(color: grid.AppPalette.textFaint, fontSize: 12),
        ),
      ),
    );
  }
}
