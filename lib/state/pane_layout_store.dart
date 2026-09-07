import 'dart:convert';

import '../core/harness_file_store.dart';
import '../core/local_key_value_store.dart';
import 'pane_preset.dart';
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

  /// Chosen shapes, by tile count. Its own key for the same reason the splits
  /// have one: an older build that cannot read it should lose the shape, not
  /// the whole layout.
  static const _presetsKey = 'terminal_pane_presets';

  /// The ceiling on tiles, enforced on the way IN as well as out: a file written
  /// by a future build that allows more must not make this one try to open
  /// terminals it has nowhere to put.
  ///
  /// Nine, because ⌘1–⌘9 already addresses that many and a tenth would have no
  /// key. It is a CEILING, not a target — how many actually fit is decided by
  /// the window, since every terminal has a floor of 40 columns and 12 rows
  /// that both this app and the daemon enforce. On a 1280px window with the
  /// rail open that is about three columns; on a 2560px display, six.
  static const maxPanes = 9;

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

  /// Chosen shapes, by tile count. An id this build does not know is dropped —
  /// a shape it cannot draw is worse than the default it can.
  Future<Map<int, PanePreset>> loadPresets() async {
    try {
      final raw = await _storage.read(_presetsKey);
      if (raw == null || raw.isEmpty) return const {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final out = <int, PanePreset>{};
      for (final entry in decoded.entries) {
        final count = int.tryParse(entry.key.toString());
        if (count == null || count < 2 || count > maxPanes) continue;
        final preset = PanePreset.byId(entry.value?.toString());
        if (preset == null) continue;
        if (!PanePreset.forCount(count).contains(preset)) continue;
        out[count] = preset;
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  Future<void> savePresets(Map<int, PanePreset> presets) async {
    try {
      await _storage.write(
        _presetsKey,
        jsonEncode({
          for (final entry in presets.entries) '${entry.key}': entry.value.id,
        }),
      );
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
