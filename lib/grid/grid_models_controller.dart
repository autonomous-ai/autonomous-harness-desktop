import 'package:flutter/foundation.dart';

import 'grid_api_client.dart';

/// What the model picker is showing, for ONE provider.
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

/// The models each grid serves, loaded on demand and kept PER PROVIDER.
///
/// Two calls deep — a relay key first, then that relay's own `/models` — so it
/// is deliberately lazy: nothing here runs until a picker is opened.
///
/// ⚠️ It used to hold exactly one network's answer at a time, which was right
/// while the only reader was a menu listing the models of the one grid the
/// sidebar had picked. The picker now lists EVERY enabled provider at once
/// (`widgets/model_picker_dialog.dart`), so a single slot would have each
/// provider's answer evicting the last one's and the panel would show one
/// section filled and the rest perpetually loading. Keyed by network id, an
/// answer lands in its own slot and a grid the user is not looking at costs
/// nothing but the map entry.
///
/// The staleness guard the single-slot version needed is gone with it: a reply
/// is written under the id it was asked for, so a switch mid-flight can no
/// longer land one grid's models under another grid's name.
class GridModelsController extends ChangeNotifier {
  GridModelsController({GridApiClient? client})
    : _client = client ?? GridApiClient();

  final GridApiClient _client;

  final Map<String, GridModelsState> _states = <String, GridModelsState>{};

  bool _disposed = false;

  /// What is known about [networkId] — [GridModelsIdle] for one never asked
  /// about, which is a real state and not an error: nothing has been requested
  /// yet.
  GridModelsState stateFor(String networkId) =>
      _states[networkId] ?? const GridModelsIdle();

  /// Loads [networkId]'s models unless they are already loaded or in flight.
  /// Cheap to call from `build` or a picker's open callback.
  void ensureLoadedFor(String networkId) {
    final state = _states[networkId];
    if (state is GridModelsReady || state is GridModelsLoading) return;
    refresh(networkId);
  }

  /// The same for a whole list — what a picker showing every enabled provider
  /// asks for as it opens.
  ///
  /// The calls run together rather than in sequence: they are independent HTTP
  /// round trips against different relays, and awaiting them one after another
  /// would make the last provider's section wait out every section above it.
  void ensureLoadedForAll(Iterable<String> networkIds) {
    for (final networkId in networkIds) {
      if (networkId.isEmpty) continue;
      ensureLoadedFor(networkId);
    }
  }

  Future<void> refresh(String networkId) async {
    _set(networkId, const GridModelsLoading());
    try {
      final credentials = await _client.credentials(networkId);
      final models = await _client.models(
        baseUrl: credentials.baseUrl,
        apiKey: credentials.apiKey,
      );
      _set(networkId, GridModelsReady(models));
    } catch (error) {
      _set(networkId, GridModelsFailed('$error'));
    }
  }

  void _set(String networkId, GridModelsState next) {
    if (_disposed) return;
    _states[networkId] = next;
    notifyListeners();
  }

  /// Test-only: sets the state for [networkId] directly, without a real round
  /// trip through [refresh].
  ///
  /// A picker that watches this controller has to rebuild an ALREADY-OPEN panel
  /// as a real `refresh` moves a provider Idle → Loading → Ready/Failed — that
  /// live transition is exactly the thing a widget test needs to drive
  /// deterministically, and faking a whole HTTP round trip is the wrong tool
  /// for it.
  @visibleForTesting
  void debugSetState(String networkId, GridModelsState state) =>
      _set(networkId, state);

  /// Test-only: back to knowing nothing, so one test's providers cannot leak
  /// into the next one's picker.
  @visibleForTesting
  void debugClear() {
    _states.clear();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Shared by the agent header's model pill (`widgets/agent_model_menu.dart`)
/// and the picker it opens (`widgets/model_picker_dialog.dart`) — one cache, so
/// the two cannot hold half-stale copies of the same list.
final gridModelsController = GridModelsController();
