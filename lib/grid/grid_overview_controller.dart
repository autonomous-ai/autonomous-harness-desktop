import 'dart:async';

import 'package:flutter/foundation.dart';

import 'grid_api_client.dart';
import 'grid_overview.dart';
import 'grid_selection_store.dart';

/// The status rail's data: what the chosen grid is made of, kept current.
///
/// Polling rather than a socket, because the relay has no push and the figures
/// do not need one — the rollup it answers with is recomputed about once a
/// minute, so anything faster would redraw the same numbers.
///
/// The last good answer is **kept on screen while a refresh runs and when one
/// fails**. A rail that blanked every minute would be worse than no rail, and a
/// grid that went briefly unreachable is not news the bottom of the window
/// should shout: [stale] says so quietly instead.
class GridOverviewController extends ChangeNotifier {
  GridOverviewController({
    GridApiClient? api,
    GridSelectionStore? selection,
    this.interval = const Duration(seconds: 60),
  }) : _api = api ?? GridApiClient(),
       _selection = selection ?? gridSelectionStore {
    _selection.addListener(_onSelectionChanged);
    _onSelectionChanged();
  }

  final GridApiClient _api;
  final GridSelectionStore _selection;

  /// How often to ask again.
  final Duration interval;

  GridOverview? overview;
  GridPower? power;

  /// People on this grid, or null when the roster is not ours to read.
  int? members;

  bool loading = false;

  /// The last fetch failed and what is on screen is the answer before it.
  bool stale = false;

  String? get networkId => _selection.value.networkId;
  String get gridName => _selection.value.label;
  bool get hasGrid => _selection.value.hasGrid;

  Timer? _timer;
  bool _disposed = false;
  int _request = 0;

  void _onSelectionChanged() {
    final id = networkId;
    if (id == _loadedFor) return;
    _loadedFor = id;
    overview = null;
    power = null;
    members = null;
    stale = false;
    _timer?.cancel();
    if (id == null) {
      notifyListeners();
      return;
    }
    unawaited(refresh());
    _timer = Timer.periodic(interval, (_) => unawaited(refresh()));
  }

  String? _loadedFor;

  Future<void> refresh() async {
    final id = networkId;
    if (id == null) return;
    final request = ++_request;
    loading = true;
    _notify();
    try {
      // The relay key is minted fresh each time rather than cached — see
      // [GridCredentials] for why — and it is the same call the New agent
      // dialog makes, so this costs nothing new on the control plane.
      final credentials = await _api.credentials(id);
      final loaded = await _api.overview(
        baseUrl: credentials.baseUrl,
        apiKey: credentials.apiKey,
      );
      if (request != _request || _disposed) return;
      overview = loaded;
      power = gridPowerFrom(loaded);
      stale = false;
    } on Object {
      if (request != _request || _disposed) return;
      // Keep whatever is on screen. A grid that answered a minute ago has not
      // stopped existing because one request timed out.
      stale = overview != null;
    }
    loading = false;
    _notify();
    // Separate and after, because it is allowed to fail on its own — a grid
    // somebody else owns refuses the roster and still has every other figure.
    await _loadMembers(id, request);
  }

  Future<void> _loadMembers(String id, int request) async {
    final count = await _api.memberCount(id);
    if (request != _request || _disposed) return;
    members = count;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _selection.removeListener(_onSelectionChanged);
    super.dispose();
  }
}

/// `1.0 TB`, `192 GB`, `4.5 GB` — a memory figure at the scale it is read at.
String formatMemoryGb(double gb) {
  if (gb >= 1000) return '${(gb / 1024).toStringAsFixed(1)} TB';
  if (gb >= 100) return '${gb.round()} GB';
  return '${gb.toStringAsFixed(1)} GB';
}

/// `1.0 / 1.7 TB` — both halves in one unit, chosen by the larger.
String formatMemoryPair(double used, double total) {
  if (total >= 1000) {
    return '${(used / 1024).toStringAsFixed(1)} / '
        '${(total / 1024).toStringAsFixed(1)} TB';
  }
  return '${used.round()} / ${total.round()} GB';
}

/// `92.4M`, `8.5k`, `912` — a token count as people say one.
String formatTokens(int value) {
  if (value >= 1000000000) {
    return '${(value / 1000000000).toStringAsFixed(1)}B';
  }
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
  return '$value';
}

/// The window a figure covers, as a suffix: `24h`, `1h`, `15m`.
///
/// Attached to the unit rather than to the value so the figure itself stays the
/// thing the eye lands on. Empty when the relay reported no span, which is the
/// one case where a made-up window would misrepresent a real number.
String formatWindow(int seconds) {
  if (seconds <= 0) return '';
  // Days only from two up. A day is "24h" to everyone who talks about how much
  // a machine did today, and "1d" in that sentence reads like a unit conversion
  // rather than a span — which matters, because 86400 is the relay's default
  // and so the string nearly every figure will carry.
  if (seconds % 86400 == 0 && seconds >= 172800) return '${seconds ~/ 86400}d';
  if (seconds % 3600 == 0) return '${seconds ~/ 3600}h';
  if (seconds % 60 == 0) return '${seconds ~/ 60}m';
  return '${seconds}s';
}
