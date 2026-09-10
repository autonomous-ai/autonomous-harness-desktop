import 'dart:io';

import 'package:flutter/services.dart';

/// Flutter's own `Clipboard` (package:flutter/services.dart) only ever exposes `text/plain` — see
/// `widgets/terminal_panel.dart`'s `_paste()`. Reading a real IMAGE off the clipboard (a
/// screenshot, "Copy Image" from a browser, ...) needs a native round trip instead: NSPasteboard on
/// macOS (`macos/Runner/MainFlutterWindow.swift`), the GTK clipboard on Linux
/// (`linux/runner/my_application.cc`). Both answer over the same channel name and method, so this
/// wrapper is the one place call sites need to know about.
class NativeClipboard {
  NativeClipboard._();

  static const MethodChannel _channel = MethodChannel('harness/clipboard_image');

  /// Reads the system clipboard for an image, returned as PNG bytes.
  ///
  /// Returns `null` on any platform without a native handler for this channel (Windows — the
  /// runner is unexercised, see CLAUDE.md — and any platform that isn't macOS/Linux) or when the
  /// clipboard genuinely holds no image, so call sites can use one check to fall through to
  /// today's text-paste behavior either way.
  static Future<Uint8List?> readImagePng() async {
    if (!Platform.isMacOS && !Platform.isLinux) return null;
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('readImagePng');
      return bytes;
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
