import 'package:flutter/foundation.dart';

import '../core/harness_file_store.dart';
import '../core/local_key_value_store.dart';
import '../grid/grid_selection_store.dart';
import '../grid/grid_surface.dart';

/// Which grid THIS COMPUTER serves — kept apart from the one Settings ▸
/// Providers marks `DEFAULT`.
///
/// The two used to be one value, and reading [GridSelectionStore] for both made
/// a single switch answer two unrelated questions:
///
///   * **Providers' default** — where an agent I start gets its credentials.
///     A question about what this machine *consumes*.
///   * **Share Intelligence** — who my hardware and my keys answer for. A
///     question about what this machine *gives*.
///
/// Someone whose agents run on the company grid while their Mac serves a lab
/// grid had no way to say so: pointing the share elsewhere silently moved every
/// new agent with it. This store is the second half of that pair.
///
/// ### Absent means "follow the default", not "no grid"
///
/// [ShareTarget.followDefault] is the value of a machine that has never used
/// this picker, and it resolves to whatever Providers has — so the behaviour
/// before this store existed is exactly the behaviour of a fresh install, and
/// nobody has to discover a new setting to keep what they had. It is only once
/// somebody picks here that the two part company, which is the moment they
/// asked for them to.
///
/// A pin is deliberately NOT cleared when Providers' default moves: pinning is
/// the statement "I mean this one whatever that one does", and a pin that
/// followed the default would be no pin at all.
@immutable
class ShareTarget {
  const ShareTarget({this.networkId, this.networkName});

  /// Nothing pinned: this computer serves whatever Providers points at.
  static const followDefault = ShareTarget();

  final String? networkId;

  /// Stored beside the id for the reason [GridSelection] stores one: the rail
  /// names the grid in its first frame, and the id alone would put
  /// `grid-3378218621364f16` in front of the reader until `/v1/grid/me`
  /// answered.
  final String? networkName;

  bool get isPinned => networkId != null && networkId!.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is ShareTarget &&
      other.networkId == networkId &&
      other.networkName == networkName;

  @override
  int get hashCode => Object.hash(networkId, networkName);
}

/// The grid a share will actually join, and where that answer came from.
///
/// [followsDefault] is not decoration — it is the difference the page has to
/// explain. A reader who sees `bubu1` here needs to know whether their agents
/// moved too, and the honest answer depends entirely on which of the two values
/// produced this one.
@immutable
class ResolvedShareTarget {
  const ResolvedShareTarget({
    required this.networkId,
    required this.networkName,
    required this.followsDefault,
  });

  final String? networkId;
  final String? networkName;

  /// True when nothing is pinned and this came from Settings ▸ Providers.
  final bool followsDefault;

  bool get hasGrid => networkId != null && networkId!.isNotEmpty;

  /// What to call this grid on screen — its name, or the bare id when the name
  /// has not been learnt yet.
  String get label => networkName?.trim().isNotEmpty ?? false
      ? networkName!.trim()
      : (networkId ?? '');

  @override
  bool operator ==(Object other) =>
      other is ResolvedShareTarget &&
      other.networkId == networkId &&
      other.networkName == networkName &&
      other.followsDefault == followsDefault;

  @override
  int get hashCode => Object.hash(networkId, networkName, followsDefault);
}

/// Which grid a share joins, given what is pinned here and what Providers has.
///
/// Pure, and the only place the precedence is written down. Both the pane and
/// its tests read it, so "the pin wins" cannot be true in one and not the
/// other.
ResolvedShareTarget resolveShareTarget(
  ShareTarget pinned,
  GridSelection providersDefault,
) => pinned.isPinned
    ? ResolvedShareTarget(
        networkId: pinned.networkId,
        networkName: pinned.networkName,
        followsDefault: false,
      )
    : ResolvedShareTarget(
        networkId: providersDefault.networkId,
        networkName: providersDefault.networkName,
        followsDefault: true,
      );

/// Remembers the grid this computer shares with.
///
/// A persisted [ValueNotifier] singleton for the reason [GridSelectionStore] is
/// one: the pane that writes it and the rail that reads it have no common
/// ancestor short of `MaterialApp`, and the choice has to survive a relaunch —
/// an engine started yesterday is still serving this morning, and a pin that
/// evaporated overnight would leave the page describing the wrong grid.
class ShareTargetStore extends ValueNotifier<ShareTarget> {
  ShareTargetStore({
    LocalKeyValueStore? storage,
    // A compile-time const in the app; see [GridSelectionStore] for why a test
    // needs to be able to pass the other value.
    @visibleForTesting this.gridSurface = kGridSurfaceEnabled,
  }) : _storage = storage ?? HarnessFileStore.shared,
       super(ShareTarget.followDefault);

  static const _networkIdKey = 'share_target_network_id';
  static const _networkNameKey = 'share_target_network_name';

  final LocalKeyValueStore _storage;

  /// See the constructor: [kGridSurfaceEnabled], and only a test passes another.
  final bool gridSurface;

  /// Read the pin, if there is one.
  ///
  /// Failure lands on [ShareTarget.followDefault], which is the same as never
  /// having pinned: sharing goes where Providers points, exactly as it did
  /// before this setting existed. An unreadable state file is not a reason to
  /// refuse to share.
  ///
  /// A build with [kGridSurfaceEnabled] off reads nothing, for the reason
  /// [GridSelectionStore.load] gives — `state.json` is shared with the debug
  /// build that CAN reach this picker, and a release build would otherwise
  /// point its engine at a grid it draws no way to see or change.
  Future<void> load() async {
    if (!gridSurface) {
      value = ShareTarget.followDefault;
      return;
    }
    try {
      final id = await _storage.read(_networkIdKey);
      if (id == null || id.isEmpty) {
        value = ShareTarget.followDefault;
        return;
      }
      value = ShareTarget(
        networkId: id,
        networkName: await _storage.read(_networkNameKey),
      );
    } catch (_) {
      value = ShareTarget.followDefault;
    }
  }

  /// Serve [networkId] whatever Providers is set to.
  Future<void> pin({required String networkId, required String networkName}) =>
      _write(ShareTarget(networkId: networkId, networkName: networkName));

  /// Go back to serving whatever Providers points at.
  Future<void> followDefault() => _write(ShareTarget.followDefault);

  /// The notifier moves FIRST and the disk write is awaited after, so the
  /// picker settles on the click rather than on the filesystem — the same trade
  /// [GridSelectionStore] makes.
  Future<void> _write(ShareTarget next) async {
    if (value == next) return;
    value = next;
    try {
      await _put(_networkIdKey, next.networkId);
      await _put(_networkNameKey, next.networkName);
    } catch (_) {
      // Kept in memory for this run; see [load].
    }
  }

  Future<void> _put(String key, String? value) => value == null || value.isEmpty
      ? _storage.delete(key)
      : _storage.write(key, value);
}

/// The one instance the app reads.
final shareTargetStore = ShareTargetStore();
