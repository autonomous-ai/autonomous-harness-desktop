import 'dart:convert';

import '../core/harness_file_store.dart';
import '../core/local_key_value_store.dart';
import 'pane_splits.dart';
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

  /// A SECOND key rather than a field on the layout entries. The two answer
  /// different questions — which agents were open, and where the dividers sat —
  /// and the entry schema above already refuses anything it does not recognise,
  /// so widening it would make an old build drop a new build's whole layout
  /// rather than just the part it cannot use.
  static const _splitsKey = 'terminal_pane_splits';

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
  /// Divider positions, by pane count. Missing or unreadable → centred.
  Future<Map<int, PaneSplits>> loadSplits() async {
    try {
      final raw = await _storage.read(_splitsKey);
      if (raw == null || raw.isEmpty) return const {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final out = <int, PaneSplits>{};
      for (final entry in decoded.entries) {
        final count = int.tryParse(entry.key.toString());
        // A count this build cannot lay out is dropped rather than kept: it
        // would be dead weight now and a lie if the grid's shape changes.
        if (count == null || count < 2 || count > maxPanes) continue;
        out[count] = PaneSplits.fromJson(entry.value);
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  Future<void> saveSplits(Map<int, PaneSplits> splits) async {
    try {
      final payload = <String, dynamic>{
        for (final entry in splits.entries)
          // Centred is the default, so writing it only grows the file and
          // gives a future build something to misread.
          if (!entry.value.isDefault) '${entry.key}': entry.value.toJson(),
      };
      await _storage.write(_splitsKey, jsonEncode(payload));
    } catch (_) {
      // Kept in memory for this run; see above.
    }
  }

  Future<void> save(List<PaneLayoutEntry> entries) async {
    try {
      final capped = entries.take(maxPanes).map((e) => e.toJson()).toList();
      await _storage.write(_key, jsonEncode(capped));
    } catch (_) {
      // Kept in memory for this run; see above.
    }
  }
}
