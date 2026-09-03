import 'package:flutter/foundation.dart';

import 'grid_api_client.dart';

/// What the model picker is showing.
sealed class GridModelsState {
  const GridModelsState();
}

class GridModelsIdle extends GridModelsState {
  const GridModelsIdle();
}

class GridModelsLoading extends GridModelsState {
  const GridModelsLoading();
}

class GridModelsReady extends GridModelsState {
  const GridModelsReady(this.models);

  final List<String> models;
}

class GridModelsFailed extends GridModelsState {
  const GridModelsFailed(this.message);

  final String message;
}

/// The models one grid serves, loaded on demand.
///
/// Two calls deep — a relay key first, then the relay's own `/models` — so it
/// is deliberately lazy: nothing here runs until a menu is opened. Keyed by
/// network id so switching grids invalidates the list rather than showing the
/// previous grid's models under the new grid's name.
class GridModelsController extends ChangeNotifier {
  GridModelsController({GridApiClient? client})
    : _client = client ?? GridApiClient();

  final GridApiClient _client;

  String? _networkId;
  GridModelsState _state = const GridModelsIdle();
  GridModelsState get state => _state;

  /// Which grid [state] describes — null before anything is loaded.
  String? get networkId => _networkId;

  bool _disposed = false;

  /// Loads [networkId]'s models unless they are already loaded or in flight.
  /// Cheap to call from `build` or a menu's open callback.
  void ensureLoadedFor(String networkId) {
    if (_networkId == networkId &&
        (_state is GridModelsReady || _state is GridModelsLoading)) {
      return;
    }
    refresh(networkId);
  }

  Future<void> refresh(String networkId) async {
    _networkId = networkId;
    _set(const GridModelsLoading());
    try {
      final credentials = await _client.credentials(networkId);
      final models = await _client.models(
        baseUrl: credentials.baseUrl,
        apiKey: credentials.apiKey,
      );
      // The user can switch grids while this is in flight; the answer to the
      // question they stopped asking must not land on the one they are asking
      // now.
      if (_networkId != networkId) return;
      _set(GridModelsReady(models));
    } catch (error) {
      if (_networkId != networkId) return;
      _set(GridModelsFailed('$error'));
    }
  }

  void _set(GridModelsState next) {
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

/// Shared by the sidebar's model menu and anything else that needs the list.
final gridModelsController = GridModelsController();
