import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/harness_file_store.dart';
import '../core/local_key_value_store.dart';

/// Which limit warnings have been waved away, and until when.
///
/// The strip above the status rail may appear at most once per rate-limit
/// window, and this is what enforces it: closing it writes the window's key
/// here with the moment that window starts over, and nothing is offered again
/// until then. Without this the strip would reappear on the next poll — sixty
/// seconds after somebody closed it — which is how a warning becomes something
/// people dismiss without reading.
///
/// **Every entry expires.** A dismissal is about one cycle of one window, so it
/// lapses when that cycle does; expired rows are pruned on load and on every
/// write, which is why this file never grows and why "off" can never quietly
/// become "off forever". That is also why there is no permanent opt-out: an
/// off switch with no way back is a setting, and this is a warning that already
/// costs nothing once a window has reset.
///
/// A persisted [ValueNotifier] singleton like `modelRecentsStore`, in
/// `state.json` — a handful of short strings, which is what that file is for.
class UsageNudgeStore extends ValueNotifier<Map<String, DateTime>> {
  UsageNudgeStore({LocalKeyValueStore? storage})
    : _storage = storage ?? HarnessFileStore.shared,
      super(const {});

  static const _key = 'usage_limit_dismissals';

  final LocalKeyValueStore _storage;

  /// Read the saved dismissals, dropping any whose window has already reset.
  ///
  /// Failure is silent and lands on "nothing dismissed", which is the same as a
  /// fresh install: an unreadable preferences file must cost the reader a
  /// silence, never the warning itself.
  Future<void> load({DateTime? now}) async {
    try {
      final raw = await _storage.read(_key);
      if (raw == null || raw.isEmpty) return;
      value = _prune(_decode(raw), now);
    } catch (_) {
      value = const {};
    }
  }

  /// Whether [key] is still inside a dismissal.
  bool isDismissed(String key, {DateTime? now}) {
    final until = value[key];
    if (until == null) return false;
    return until.isAfter(now ?? DateTime.now());
  }

  /// Silence [key] until [until].
  ///
  /// The notifier moves FIRST and the write is awaited after, so the strip
  /// closes on the frame it was clicked rather than whenever the disk catches
  /// up — the same trade `ModelRecentsStore.remember` makes.
  Future<void> dismiss(String key, DateTime until, {DateTime? now}) async {
    value = _prune({...value, key: until}, now);
    try {
      await _storage.write(_key, _encode(value));
    } catch (_) {
      // Kept in memory for this run; see above.
    }
  }

  static Map<String, DateTime> _prune(
    Map<String, DateTime> entries,
    DateTime? now,
  ) {
    final at = now ?? DateTime.now();
    return {
      for (final entry in entries.entries)
        if (entry.value.isAfter(at)) entry.key: entry.value,
    };
  }

  static Map<String, DateTime> _decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const {};
    return {
      for (final entry in decoded.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: ?DateTime.tryParse(entry.value as String),
    };
  }

  static String _encode(Map<String, DateTime> entries) => jsonEncode({
    for (final entry in entries.entries)
      entry.key: entry.value.toIso8601String(),
  });
}

/// The one instance the app reads. Loaded by `loadPersistedSettings()`.
final usageNudgeStore = UsageNudgeStore();
