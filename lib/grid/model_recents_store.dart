import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/harness_file_store.dart';
import '../core/local_key_value_store.dart';
import 'model_picker_options.dart';

/// The last few models picked, most recent first.
///
/// An account on several providers serves more models than a panel shows at
/// once, and the ones a person actually uses are two or three — so the picker
/// puts them at the top rather than making somebody scroll past forty rows to
/// the one they used an hour ago. The same section OpenCode's model dialog
/// opens with.
///
/// A persisted [ValueNotifier] singleton like `gridSelectionStore`, loaded
/// before the first frame (`core/startup.dart`): the picker is a list whose top
/// section would otherwise arrive a frame after the panel and push every row
/// down under a pointer already on its way to one.
///
/// ⚠️ Only picks that name a PROVIDER are remembered. "No provider" is already
/// a permanent row at the top of the list, so a recent copy of it would be the
/// same row twice — and the one thing a Recent section must not do is make the
/// list longer without making it faster.
class ModelRecentsStore extends ValueNotifier<List<ModelChoice>> {
  ModelRecentsStore({LocalKeyValueStore? storage})
    : _storage = storage ?? HarnessFileStore.shared,
      super(const []);

  static const _key = 'grid_recent_models';

  /// Short on purpose. This is a shortcut to what you just used, not a history:
  /// a section long enough to scroll is the list it exists to save you from.
  static const int max = 5;

  final LocalKeyValueStore _storage;

  /// Read the saved picks, if there are any.
  ///
  /// Failure is silent and lands on "nothing recent", which is the same as a
  /// fresh install: an unreadable preferences file must cost the reader a
  /// shortcut, never the picker itself.
  Future<void> load() async {
    try {
      final raw = await _storage.read(_key);
      if (raw == null || raw.isEmpty) return;
      value = _decode(raw);
    } catch (_) {
      value = const [];
    }
  }

  /// Move [choice] to the front — or add it there, dropping the oldest once the
  /// list is full.
  ///
  /// The notifier moves FIRST and the write is awaited after, so a panel
  /// reopened immediately shows the pick that was just made rather than
  /// whatever the disk has caught up to — the same trade `ThemeModeStore` and
  /// `GridSelectionStore` make.
  Future<void> remember(ModelChoice choice) async {
    if (!choice.hasProvider) return;
    final next = <ModelChoice>[
      choice,
      // Value equality on (networkId, model), so re-picking a model already in
      // the list moves it rather than repeating it.
      for (final existing in value)
        if (existing != choice) existing,
    ];
    value = next.length <= max ? next : next.sublist(0, max);
    try {
      await _storage.write(_key, _encode(value));
    } catch (_) {
      // Kept in memory for this run; see above.
    }
  }

  /// A provider dropped from the account — or switched off here — leaves rows
  /// that name nothing. They are inert (the picker only shows a recent whose
  /// provider is in the list it was given), so they are not swept: a provider
  /// switched off in Settings is expected back, and forgetting its picks would
  /// punish a reader for having looked at a switch.
  static List<ModelChoice> _decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final entry in decoded)
        if (entry is Map &&
            entry['n'] is String &&
            (entry['n'] as String).isNotEmpty)
          ModelChoice(
            networkId: entry['n'] as String,
            model: entry['m'] is String ? entry['m'] as String : null,
          ),
    ];
  }

  /// The provider's NAME is deliberately not stored: it is rebuilt from the
  /// live provider list when the section is drawn, so a grid renamed since the
  /// pick was made reads under the name it has now.
  static String _encode(List<ModelChoice> choices) => jsonEncode([
    for (final choice in choices)
      {'n': choice.networkId, if (choice.model != null) 'm': choice.model},
  ]);
}

/// The one instance the app reads — see `gridSelectionStore` for why a store
/// lives beside its model rather than beside `main()`.
final modelRecentsStore = ModelRecentsStore();
