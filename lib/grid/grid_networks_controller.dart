import 'package:flutter/foundation.dart';

import 'grid_api_client.dart';
import 'grid_network.dart';

/// What the Grid screen is showing right now.
///
/// A sealed family rather than a status enum beside a nullable payload and a
/// nullable error: the three states carry different data, and this is what
/// makes it impossible to render a list that isn't there or an error that has
/// been cleared.
sealed class GridNetworksState {
  const GridNetworksState();
}

/// Nothing asked for yet — the screen has not been opened this visit.
class GridNetworksIdle extends GridNetworksState {
  const GridNetworksIdle();
}

class GridNetworksLoading extends GridNetworksState {
  const GridNetworksLoading();
}

class GridNetworksReady extends GridNetworksState {
  const GridNetworksReady(this.me);

  final GridMe me;
}

class GridNetworksFailed extends GridNetworksState {
  const GridNetworksFailed(this.message);

  /// Already user-facing — [GridApiClient] turns the API's own failure shapes
  /// into a sentence before it gets here.
  final String message;
}

/// Loads the grids this account is on, and holds the answer for as long as
/// Settings is open.
///
/// Owned by the Settings screen rather than by the section widget: the rail
/// mounts and unmounts panes as you move between them, so a controller living
/// in the pane would refetch every time the user came back to it.
class GridNetworksController extends ChangeNotifier {
  GridNetworksController({GridApiClient? client})
    : _client = client ?? GridApiClient();

  final GridApiClient _client;

  GridNetworksState _state = const GridNetworksIdle();
  GridNetworksState get state => _state;

  bool _disposed = false;

  /// Loads once. Cheap to call from `build`, which is the point — the pane asks
  /// on every rebuild and only the first one does anything.
  void ensureLoaded() {
    if (_state is GridNetworksIdle) refresh();
  }

  /// Loads again, whatever the current state — the refresh button.
  Future<void> refresh() async {
    if (_state is GridNetworksLoading) return;
    _set(const GridNetworksLoading());
    try {
      _set(GridNetworksReady(await _client.me()));
    } catch (error) {
      _set(GridNetworksFailed('$error'));
    }
  }

  void _set(GridNetworksState next) {
    // The load outlives the screen when Settings is closed mid-flight, and
    // notifying a disposed ChangeNotifier throws.
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
