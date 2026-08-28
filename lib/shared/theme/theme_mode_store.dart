import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/harness_file_store.dart';
import '../../core/local_key_value_store.dart';

/// Which theme the user chose, remembered across launches.
///
/// A [ValueNotifier] rather than something in [AppState] on purpose: the theme
/// is read by the widget that builds `MaterialApp`, which sits *above* every
/// provider scope the rest of the app lives in, and it must resolve before
/// there is any session, machine or connection to hang it off. It is also the
/// one setting that means something before sign-in.
///
/// [ThemeMode.system] is the default because it is the only value that can be
/// right without asking: the person already told their computer which they
/// wanted, and a first launch that ignores that is a first impression of an app
/// that does not pay attention.
class ThemeModeStore extends ValueNotifier<ThemeMode> {
  ThemeModeStore({LocalKeyValueStore? storage})
    : _storage = storage ?? HarnessFileStore.shared,
      super(ThemeMode.system);

  static const _key = 'app_theme_mode';

  /// Kept in step with AppKit, which Flutter's theme does not reach.
  ///
  /// The standard About panel, the menu bar and the window's own title bar all
  /// follow `NSApp.appearance`, not `MaterialApp.themeMode`. Without this, Light
  /// on a Mac set to Dark gives a white app with a black title bar and a black
  /// About box — which looks like the theme was only half done.
  ///
  /// Failure is swallowed: this is chrome. A platform with no such channel (a
  /// test, a future Linux build) must not take the theme down with it.
  static const _appearance = MethodChannel('harness/appearance');

  Future<void> _syncNativeAppearance(ThemeMode mode) async {
    try {
      await _appearance.invokeMethod<void>('set', switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => null,
      });
    } catch (_) {
      // Chrome only; see above.
    }
  }

  final LocalKeyValueStore _storage;

  /// Read the saved choice, if there is one.
  ///
  /// Failure is silent and lands on [ThemeMode.system]. An unreadable state file
  /// is a reason to paint the window the way the OS asked; it is not a reason to
  /// refuse to start, and it is not worth a dialog in front of someone who only
  /// wanted to open a terminal.
  Future<void> load() async {
    try {
      final saved = await _storage.read(_key);
      value = _parse(saved) ?? ThemeMode.system;
    } catch (_) {
      value = ThemeMode.system;
    }
    await _syncNativeAppearance(value);
  }

  /// Choose a mode and remember it.
  ///
  /// The notifier moves FIRST and the write is awaited after, so the window
  /// repaints on the click rather than on the disk. A failed write costs the
  /// choice at the next launch, which is a far smaller wrong than a theme that
  /// visibly lags the menu it was chosen from.
  Future<void> select(ThemeMode mode) async {
    if (value == mode) return;
    value = mode;
    unawaited(_syncNativeAppearance(mode));
    try {
      await _storage.write(_key, _name(mode));
    } catch (_) {
      // Kept in memory for this run; see above.
    }
  }

  /// Stored as a word rather than an index: an enum's ordinal is a detail of the
  /// order its cases happen to be written in, and a saved file outlives that.
  static String _name(ThemeMode mode) => switch (mode) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };

  static ThemeMode? _parse(String? raw) => switch (raw) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    'system' => ThemeMode.system,
    _ => null,
  };
}

/// The one instance the app reads.
///
/// It lives HERE rather than beside `main()`, and that is a dependency-direction
/// choice rather than tidiness: the menu that changes the theme is a widget, and
/// a widget reaching up into `main.dart` for a global would drag the whole app
/// entrypoint — `runApp`, the provider scope, every screen it routes to — into
/// anything that renders that widget, tests included.
final themeModeStore = ThemeModeStore();
