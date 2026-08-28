import 'dart:convert';

import '../core/harness_file_store.dart';
import '../core/local_key_value_store.dart';
import 'terminal_pane.dart';

/// Remembers which agents were on screen, so reopening the app returns to the
/// desk it was left on rather than to whatever happens to load first.
///
/// Only the intent is stored — machine and agent ids. Sizes, sessions and
/// stream ids are all facts about a particular run and would be lies by the
/// next one.
class PaneLayoutStore {
  PaneLayoutStore({LocalKeyValueStore? storage})
    : _storage = storage ?? HarnessFileStore.shared;

  static const _key = 'terminal_pane_layout';

  /// Four, matching the grid. Enforced on the way IN as well as out: a file
  /// written by a future build that allows more must not make this one try to
  /// open five terminals it has nowhere to put.
  static const maxPanes = 4;

  final LocalKeyValueStore _storage;

  /// Failure is silent and lands on an empty layout, which is exactly the
  /// first-run state. A corrupt state file is a reason to open the app the way
  /// a new user sees it, not a reason to refuse to start.
  Future<List<PaneLayoutEntry>> load() async {
    try {
      final raw = await _storage.read(_key);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final entries = <PaneLayoutEntry>[];
      for (final item in decoded) {
        final entry = PaneLayoutEntry.fromJson(item);
        // One agent cannot be in two tiles: the daemon keeps a single
        // controller per agent, so a duplicate would take its own twin over the
        // moment both opened. Dropping it here means a hand-edited or
        // downgraded file cannot produce that fight.
        if (entry == null ||
            entries.any(
              (existing) =>
                  existing.machineId == entry.machineId &&
                  existing.agentId == entry.agentId,
            )) {
          continue;
        }
        entries.add(entry);
        if (entries.length == maxPanes) break;
      }
      return entries;
    } catch (_) {
      return const [];
    }
  }

  /// A failed write costs the layout at the next launch, which is a far smaller
  /// wrong than an exception thrown out of a pane close.
  Future<void> save(List<PaneLayoutEntry> entries) async {
    try {
      final capped = entries.take(maxPanes).map((e) => e.toJson()).toList();
      await _storage.write(_key, jsonEncode(capped));
    } catch (_) {
      // Kept in memory for this run; see above.
    }
  }
}
