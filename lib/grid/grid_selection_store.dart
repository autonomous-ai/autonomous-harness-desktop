import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/harness_file_store.dart';
import '../core/local_key_value_store.dart';
import 'grid_surface.dart';

/// What running on no provider is called on screen.
///
/// ⚠️ **This used to read `No provider`, and that was the bug.** The rail's
/// pill prints `Subscription` for this exact state, so a person clicked a pill
/// saying one thing and found the tick sitting beside another — two names for
/// one state, and the one in the menu named an absence. The old reasoning was
/// that a menu row may fairly be named for what it is NOT while a readout must
/// say what IS; that holds for a row nobody chooses on purpose, and this is not
/// one. Switching every provider off is a deliberate, supported setup, and what
/// it selects is a real thing: the engine subscriptions already signed in on
/// this computer. It gets the name of that thing.
///
/// One word, shared with the pill, so the two can never drift apart again.
///
/// ⚠️ Settings ▸ Providers does not print this: it dropped the row that named
/// this state, because a state is not a provider and the list is a list of
/// providers. Every switch being off IS this state there. The sidebar pill
/// keeps the row — it is a picker, not a roster, and "use nothing" is a real
/// thing to pick from it.
const String kNoGridTargetLabel = 'Subscription';

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

  /// What to print for this selection WHATEVER it is — a grid's name, or the
  /// label that stands for having picked none. [label] answers only half of
  /// that, and every caller was completing it with the same ternary.
  String get targetLabel => hasGrid ? label : kNoGridTargetLabel;

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
  GridSelectionStore({
    LocalKeyValueStore? storage,
    // A compile-time const in the app, which makes the shipped build's own
    // behaviour — a persisted grid left unread — unreachable from a test run,
    // where it is always true. Passed in so that case can be asserted.
    @visibleForTesting this._gridSurface = kGridSurfaceEnabled,
  }) : _storage = storage ?? HarnessFileStore.shared,
       super(GridSelection.none);

  static const _networkIdKey = 'grid_selected_network_id';
  static const _networkNameKey = 'grid_selected_network_name';

  /// Left behind by a build before the model became per-agent. Never read (see [load]) — swept out
  /// in [_write] so it does not sit in `state.json` forever, waiting to resurrect the old global
  /// setting under a downgraded build.
  static const _legacyModelKey = 'grid_selected_model';

  final LocalKeyValueStore _storage;

  /// See the constructor: [kGridSurfaceEnabled], and only a test passes another.
  final bool _gridSurface;

  /// Read the saved choice, if there is one.
  ///
  /// Failure is silent and lands on [GridSelection.none], which is the same as
  /// never having chosen: agents launch the way they did before this feature
  /// existed. An unreadable state file is not a reason to refuse to start.
  ///
  /// A `grid_selected_model` key left by an older build is never read here —
  /// it named no particular agent, so there is nothing to carry forward. It is
  /// deleted the next time [_write] runs, not here — reading is not the place
  /// to also mutate the store.
  ///
  /// A build with [kGridSurfaceEnabled] off reads nothing at all. `state.json`
  /// is shared with the debug build that CAN pick a grid, so a developer's
  /// choice would otherwise reach a release build through the file and point
  /// its agents at a grid it shows no way to see, change or leave. The stored
  /// key is left alone rather than cleared: it is that other build's setting,
  /// and this one is only declining to act on it.
  Future<void> load() async {
    if (!_gridSurface) {
      value = GridSelection.none;
      return;
    }
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
      // Cheap even when the key is already gone — see [_legacyModelKey].
      await _storage.delete(_legacyModelKey);
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
