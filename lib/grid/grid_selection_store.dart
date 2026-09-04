import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/harness_file_store.dart';
import '../core/local_key_value_store.dart';

/// The grid new agents are launched against, if any.
///
/// [networkName] is stored beside the id so a reader — Settings ▸ Grid, the
/// New agent dialog — can name the grid on the first frame, before anything
/// has been fetched — the id alone would put `grid-3378218621364f16` in front
/// of the user until the control plane answered.
@immutable
class GridSelection {
  const GridSelection({this.networkId, this.networkName});

  static const none = GridSelection();

  final String? networkId;
  final String? networkName;

  bool get hasGrid => networkId != null && networkId!.isNotEmpty;

  /// What to call the chosen grid on screen.
  String get label => networkName?.trim().isNotEmpty ?? false
      ? networkName!.trim()
      : (networkId ?? '');

  @override
  bool operator ==(Object other) =>
      other is GridSelection &&
      other.networkId == networkId &&
      other.networkName == networkName;

  @override
  int get hashCode => Object.hash(networkId, networkName);
}

/// Remembers which grid new agents should run against.
///
/// A persisted [ValueNotifier] singleton, like `themeModeStore`: Settings ▸
/// Grid writes it, and it is read by the New agent dialog, the agent view's
/// header menu (`widgets/agent_model_menu.dart`), the share pane, and the
/// status rail — with no common ancestor short of `MaterialApp` between them —
/// so it has to survive a relaunch or the choice would have to be made again
/// every morning.
///
/// The model is no longer part of this: it is chosen per agent, in the agent
/// view's header — see `widgets/agent_model_menu.dart`. A model id is only
/// meaningful for the one agent it was picked for, not for "new agents" as a
/// class.
///
/// ⚠️ Choosing a grid does NOT retarget agents that are already running. It is
/// only read when an agent is created.
class GridSelectionStore extends ValueNotifier<GridSelection> {
  GridSelectionStore({LocalKeyValueStore? storage})
    : _storage = storage ?? HarnessFileStore.shared,
      super(GridSelection.none);

  static const _networkIdKey = 'grid_selected_network_id';
  static const _networkNameKey = 'grid_selected_network_name';

  final LocalKeyValueStore _storage;

  /// Read the saved choice, if there is one.
  ///
  /// Failure is silent and lands on [GridSelection.none], which is the same as
  /// never having chosen: agents launch the way they did before this feature
  /// existed. An unreadable state file is not a reason to refuse to start.
  ///
  /// A `grid_selected_model` key left by an older build is never read here —
  /// it named no particular agent, so there is nothing to carry forward.
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
      );
    } catch (_) {
      value = GridSelection.none;
    }
  }

  /// Choose a grid.
  Future<void> selectNetwork({
    required String networkId,
    required String networkName,
  }) => _write(GridSelection(networkId: networkId, networkName: networkName));

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
