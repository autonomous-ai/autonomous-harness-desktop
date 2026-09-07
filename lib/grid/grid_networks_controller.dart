import 'package:flutter/foundation.dart';

import '../analytics/analytics.dart';
import 'grid_session.dart';
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

/// This computer has no Grid session. Its own state rather than a
/// [GridNetworksFailed] carrying a 401, because the two want different buttons:
/// a failure offers Retry, and retrying a sign-out fails identically forever.
class GridNetworksSignedOut extends GridNetworksState {
  const GridNetworksSignedOut();
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
  GridNetworksController({GridApiClient? client, GridSessionStore? session})
    : _client = client ?? GridApiClient(),
      _session = session ?? gridSessionStore {
    _session.addListener(_onSession);
  }

  final GridApiClient _client;

  /// Watched, not merely read: this controller's answer DEPENDS on the session,
  /// and it is the only thing holding a stale one when a sign-in lands late.
  final GridSessionStore _session;

  GridNetworksState _state = const GridNetworksIdle();
  GridNetworksState get state => _state;

  bool _disposed = false;

  /// Loads once. Cheap to call from `build`, which is the point — the pane asks
  /// on every rebuild and only the first one does anything.
  void ensureLoaded() {
    if (_state is GridNetworksIdle) refresh();
  }

  /// A session arrived after this answered "signed out".
  ///
  /// That answer is now stale and nothing else will ask again: [ensureLoaded]
  /// only fetches from Idle, so the pane would sit on its sign-in card for the
  /// life of the screen. It is a real race on a fresh machine — the bootstrap
  /// sign-in takes a moment, and Settings can be open before it lands.
  void _onSession() {
    if (_state is GridNetworksSignedOut && _session.signedIn) refresh();
  }

  /// Loads again, whatever the current state — the refresh button.
  Future<void> refresh() async {
    if (_state is GridNetworksLoading) return;
    _set(const GridNetworksLoading());
    try {
      final me = await _client.me();
      _set(GridNetworksReady(me));
      // Once per launch, not per refresh: the refresh button and a second panel
      // would otherwise count one account several times over.
      if (!_countTracked) {
        _countTracked = true;
        analytics.gridNetworksLoaded(count: me.networks.length);
      }
    } on GridSignedOutException {
      _set(const GridNetworksSignedOut());
    } catch (error) {
      _set(GridNetworksFailed('$error'));
    }
  }

  bool _countTracked = false;

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
    // The store outlives every controller — it is a singleton — so a listener
    // left on it is a leak that also revives a disposed notifier.
    _session.removeListener(_onSession);
    super.dispose();
  }
}

/// Shared by the Settings pane and the sidebar's grid menu — two places that
/// list the same grids and must not each hold their own half-stale copy.
final gridNetworksController = GridNetworksController();
