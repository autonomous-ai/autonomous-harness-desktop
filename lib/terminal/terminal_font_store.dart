import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import '../core/harness_file_store.dart';
import '../core/local_key_value_store.dart';
import 'terminal_typography.dart';

/// A monospace font the terminal is allowed to render in.
///
/// Deliberately a closed, curated set rather than free text or a native font
/// picker: the vendored renderer measures cell width by laying out ten `'m'`
/// glyphs and dividing by 10 (`TerminalPainter._measureCharSize`), a hard
/// monospace assumption. A proportional font would misalign every column a
/// remote TUI draws regardless of how correctly resize is handled. These four
/// are the faces guaranteed present on stock macOS — nothing here needs Flutter
/// to enumerate installed fonts (it can't) or risk a silent substitution.
enum TerminalFontChoice {
  sfMono('SF Mono', terminalFontFamily, terminalFontFallback),
  menlo('Menlo', 'Menlo', ['Monaco', 'Courier New', 'monospace']),
  monaco('Monaco', 'Monaco', ['Menlo', 'Courier New', 'monospace']),
  courierNew('Courier New', 'Courier New', ['Menlo', 'Monaco', 'monospace']);

  const TerminalFontChoice(this.label, this.fontFamily, this.fontFamilyFallback);

  final String label;
  final String fontFamily;
  final List<String> fontFamilyFallback;
}

/// The user's chosen terminal typography (family + size), remembered across
/// launches.
///
/// Same shape as `ThemeModeStore` (`lib/shared/theme/theme_mode_store.dart`) —
/// a [ValueNotifier] singleton backed by [HarnessFileStore], loaded once in
/// `main()` before `runApp`.
///
/// The notifier's value IS the memoized [TerminalStyle], not a raw font/size
/// pair: [TerminalStyle] has no `==`/`hashCode` override, and the vendored
/// renderer's own setters (`RenderTerminal.textStyle`, `TerminalPainter
/// .textStyle`) short-circuit on `==`/identity before doing any work. A fresh
/// `TerminalStyle(...)` built on every widget rebuild would look like "the
/// font changed" every time and spuriously re-layout (and re-resize) the
/// terminal on every unrelated rebuild. [_styleFor] guarantees the same
/// (family, size) always returns the identical object, so both the renderer's
/// guard and [ValueNotifier]'s own "don't notify on a no-op set" work for
/// free.
class TerminalFontStore extends ValueNotifier<TerminalStyle> {
  TerminalFontStore({LocalKeyValueStore? storage})
    : _storage = storage ?? HarnessFileStore.shared,
      super(_styleFor(TerminalFontChoice.sfMono, terminalFontSize));

  static const _familyKey = 'terminal_font_family';
  static const _sizeKey = 'terminal_font_size';
  static const _minSize = 9.0;
  static const _maxSize = 22.0;
  static const _step = 1.0;

  final LocalKeyValueStore _storage;

  static final _cache = <(TerminalFontChoice, double), TerminalStyle>{};
  static TerminalStyle _styleFor(TerminalFontChoice choice, double size) =>
      _cache.putIfAbsent(
        (choice, size),
        () => TerminalStyle(
          fontSize: size,
          fontFamily: choice.fontFamily,
          fontFamilyFallback: choice.fontFamilyFallback,
        ),
      );

  TerminalFontChoice get family =>
      TerminalFontChoice.values.firstWhere(
        (choice) => choice.fontFamily == value.fontFamily,
        orElse: () => TerminalFontChoice.sfMono,
      );

  double get size => value.fontSize;

  /// Read the saved choice, if there is one. Failure (or a stale/unknown
  /// family name from an older build) is silent and lands on the default —
  /// an unreadable state file is not a reason to refuse to start.
  Future<void> load() async {
    try {
      final savedFamily = await _storage.read(_familyKey);
      final savedSize = await _storage.read(_sizeKey);
      final choice = TerminalFontChoice.values
          .where((c) => c.name == savedFamily)
          .firstOrNull;
      final size = savedSize == null ? null : double.tryParse(savedSize);
      value = _styleFor(
        choice ?? TerminalFontChoice.sfMono,
        _clamp(size ?? terminalFontSize),
      );
    } catch (_) {
      value = _styleFor(TerminalFontChoice.sfMono, terminalFontSize);
    }
  }

  Future<void> setFamily(TerminalFontChoice choice) => _set(choice, size);

  Future<void> increaseSize() => _set(family, size + _step);
  Future<void> decreaseSize() => _set(family, size - _step);
  Future<void> setSize(double size) => _set(family, size);

  Future<void> reset() => _set(TerminalFontChoice.sfMono, terminalFontSize);

  double _clamp(double size) => size.clamp(_minSize, _maxSize);

  Future<void> _set(TerminalFontChoice choice, double size) async {
    final next = _styleFor(choice, _clamp(size));
    if (next == value) return;
    value = next;
    try {
      await _storage.write(_familyKey, choice.name);
      await _storage.write(_sizeKey, next.fontSize.toString());
    } catch (_) {
      // Kept in memory for this run; see load()'s doc.
    }
  }
}

/// The one instance the app reads — same dependency-direction rationale as
/// `themeModeStore` (see `theme_mode_store.dart`): the widgets that read and
/// write this (the terminal panel, the composer, the Settings dialog, the
/// account menu) must not have to reach into `main.dart` for it.
final terminalFontStore = TerminalFontStore();
