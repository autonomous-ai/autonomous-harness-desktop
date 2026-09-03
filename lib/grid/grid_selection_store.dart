import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/harness_file_store.dart';
import '../core/local_key_value_store.dart';

/// The grid and model new agents are launched against, if any.
///
/// [networkName] is stored beside the id so the sidebar can name the grid on
/// the first frame, before anything has been fetched — the id alone would put
/// `grid-3378218621364f16` in front of the user until the control plane
/// answered.
@immutable
class GridSelection {
  const GridSelection({this.networkId, this.networkName, this.model});

  static const none = GridSelection();

  final String? networkId;
  final String? networkName;

  /// A model id as the relay lists it (`Auto`, `GLM-4.7-Flash`, …). Null means
  /// "whatever the grid picks" — the relay's own default.
  final String? model;

  bool get hasGrid => networkId != null && networkId!.isNotEmpty;

  /// What to call the chosen grid on screen.
  String get label => networkName?.trim().isNotEmpty ?? false
      ? networkName!.trim()
      : (networkId ?? '');

  @override
  bool operator ==(Object other) =>
      other is GridSelection &&
      other.networkId == networkId &&
      other.networkName == networkName &&
      other.model == model;

  @override
  int get hashCode => Object.hash(networkId, networkName, model);
}

/// Remembers which grid and model new agents should run against.
///
/// A persisted [ValueNotifier] singleton, like `themeModeStore`: the sidebar
/// shows it, Settings changes it, and the New agent dialog reads it — three
/// places with no common ancestor short of `MaterialApp`, and it has to survive
/// a relaunch or the choice would have to be made again every morning.
///
/// ⚠️ Choosing a grid does NOT retarget agents that are already running. It is
/// read when an agent is created, and that is what the sidebar's caption says.
class GridSelectionStore extends ValueNotifier<GridSelection> {
  GridSelectionStore({LocalKeyValueStore? storage})
    : _storage = storage ?? HarnessFileStore.shared,
      super(GridSelection.none);

  static const _networkIdKey = 'grid_selected_network_id';
  static const _networkNameKey = 'grid_selected_network_name';
  static const _modelKey = 'grid_selected_model';

  final LocalKeyValueStore _storage;

  /// Read the saved choice, if there is one.
  ///
  /// Failure is silent and lands on [GridSelection.none], which is the same as
  /// never having chosen: agents launch the way they did before this feature
  /// existed. An unreadable state file is not a reason to refuse to start.
  Future<void> load() async {
    try {
      final id = await _storage.read(_networkIdKey);
      if (id == null || id.isEmpty) {
        value = GridSelection.none;
        return;
      }
      value = GridSelection(
        networkId: id,
        networkName: await _storage.read(_networkNameKey),
        model: await _storage.read(_modelKey),
      );
    } catch (_) {
      value = GridSelection.none;
    }
  }

  /// Choose a grid. Clears the model, because a model id is only meaningful on
  /// the grid that serves it — carrying one across would name a model the new
  /// grid may not have.
  Future<void> selectNetwork({
    required String networkId,
    required String networkName,
  }) => _write(GridSelection(networkId: networkId, networkName: networkName));

  /// Choose a model on the grid already selected. A no-op with no grid: there
  /// is nothing for a model id to be relative to.
  Future<void> selectModel(String? model) {
    if (!value.hasGrid) return Future<void>.value();
    return _write(
      GridSelection(
        networkId: value.networkId,
        networkName: value.networkName,
        model: model,
      ),
    );
  }

  /// Back to launching agents the way the app did before a grid was ever
  /// picked — the engine's own login, whatever that is.
  Future<void> clear() => _write(GridSelection.none);

  /// The notifier moves FIRST and the write is awaited after, so the sidebar
  /// repaints on the click rather than on the disk — the same trade
  /// `ThemeModeStore.select` makes.
  Future<void> _write(GridSelection next) async {
    if (value == next) return;
    value = next;
    try {
      await _put(_networkIdKey, next.networkId);
      await _put(_networkNameKey, next.networkName);
      await _put(_modelKey, next.model);
    } catch (_) {
      // Kept in memory for this run; see above.
    }
  }

  Future<void> _put(String key, String? value) => value == null || value.isEmpty
      ? _storage.delete(key)
      : _storage.write(key, value);
}

/// The one instance the app reads. Lives here rather than beside `main()` for
/// the reason `themeModeStore` does — a widget must not have to import the
/// entrypoint to read it.
final gridSelectionStore = GridSelectionStore();
