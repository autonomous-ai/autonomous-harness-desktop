import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Load a real font.
///
/// Widget tests draw with Ahem, whose every glyph is a fixed square — a 24
/// character label measures 276px where Arial measures ~140. That is not a
/// small distortion for a surface whose whole job is fitting figures beside
/// names: with Ahem the rail's node panel overflows by 19px, and a node card
/// laid out in it is a picture of a bug that does not exist.
///
/// Shared because the node dashboard hit the same wall the rail's panels did,
/// and two copies of this is two chances for one of them to stop loading the
/// mono face and start "finding" overflows again.
Future<void> loadRealFonts() async {
  Future<ByteData> bytes(String path) async =>
      ByteData.view(Uint8List.fromList(await File(path).readAsBytes()).buffer);

  // Under every family these surfaces can resolve to: the app's own
  // `.AppleSystemUIFont`, and Roboto, which is what an unthemed widget falls
  // back to in a test.
  final sans = await bytes('/System/Library/Fonts/Supplemental/Arial.ttf');
  for (final family in ['.AppleSystemUIFont', 'Roboto', 'SF Pro Text']) {
    await (FontLoader(family)..addFont(Future.value(sans))).load();
  }
  // A model id is set in mono, and an unregistered mono family falls back to
  // Ahem just as loudly.
  final mono = await bytes(
    '/System/Library/Fonts/Supplemental/Courier New.ttf',
  );
  for (final family in ['.AppleSystemUIFontMonospaced', 'SF Mono', 'Menlo']) {
    await (FontLoader(family)..addFont(Future.value(mono))).load();
  }
}
