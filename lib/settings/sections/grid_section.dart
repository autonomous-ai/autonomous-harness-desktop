import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../grid/grid_network.dart';
import '../../grid/grid_selection_store.dart';
import '../../grid/grid_networks_controller.dart';
import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/widgets/app_icon_button.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/section_scaffold.dart';
import 'grid_network_card.dart';

/// Settings ▸ Grid: every grid this account can talk to.
///
/// Read straight from the Grid control plane over HTTPS — this screen does not
/// go through the `harness` CLI, which knows nothing about Grid accounts. See
/// [GridApiClient].
class GridSection extends StatelessWidget {
  const GridSection({super.key, required this.controller});

  final GridNetworksController controller;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    // Cheap on every rebuild: only the first call fetches.
    controller.ensureLoaded();
    return SectionScaffold(
      title: 'Grid',
      subtitle:
          'The grids your Grid account is on — who owns each one, what you may '
          'do on it, and where it signals.',
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => _Body(controller: controller),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.controller});

  final GridNetworksController controller;

  @override
  Widget build(BuildContext context) {
    return switch (controller.state) {
      GridNetworksIdle() || GridNetworksLoading() => const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      GridNetworksFailed(:final message) => _Failed(
        message: message,
        onRetry: () => unawaited(controller.refresh()),
      ),
      GridNetworksReady(:final me) => _Networks(
        controller: controller,
        email: me.user.email,
        networks: me.networks,
      ),
    };
  }
}

class _Networks extends StatelessWidget {
  const _Networks({
    required this.controller,
    required this.email,
    required this.networks,
  });

  final GridNetworksController controller;
  final String email;
  final List<GridNetwork> networks;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                email,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: grid.AppPalette.textSecondary,
                  fontSize: 12.5,
                ),
              ),
            ),
            AppIconButton(
              key: const Key('grid-refresh-button'),
              icon: LucideIcons.refreshCw300,
              size: 16,
              tooltip: 'Reload grids',
              onPressed: () => unawaited(controller.refresh()),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: networks.isEmpty
              ? const EmptyState(
                  icon: LucideIcons.zap300,
                  title: 'No grids yet',
                  message:
                      'This account is not on a grid. Join one from the Grid '
                      'app, then reload here.',
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  children: [
                    for (final network in networks)
                      ValueListenableBuilder<GridSelection>(
                        valueListenable: gridSelectionStore,
                        builder: (context, chosen, _) => GridNetworkCard(
                          network: network,
                          signedInEmail: email,
                          selected: chosen.networkId == network.networkId,
                          onUse: () => unawaited(
                            gridSelectionStore.selectNetwork(
                              networkId: network.networkId,
                              networkName: network.displayName,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// The load failed — say what went wrong and leave a way to try again, rather
/// than an empty pane that looks like an account with no grids.
class _Failed extends StatelessWidget {
  const _Failed({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Align(
      alignment: Alignment.topLeft,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: grid.AppPalette.warn.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: grid.AppPalette.warn.withValues(alpha: 0.26),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  LucideIcons.triangleAlert300,
                  size: 16,
                  color: grid.AppPalette.warn,
                ),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    'Could not load your grids',
                    style: TextStyle(
                      color: grid.AppPalette.textPrimary,
                      fontSize: 12.5,
                      fontWeight: grid.AppFont.semibold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: TextStyle(
                color: grid.AppPalette.textSecondary,
                fontSize: 12,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('grid-retry-button'),
                onPressed: onRetry,
                child: const Text(
                  'Try again',
                  style: TextStyle(fontSize: 12.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
