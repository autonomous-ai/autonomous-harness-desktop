import 'dart:io' show Platform;
import 'dart:ui' show Size;

import 'package:window_manager/window_manager.dart';

/// Puts the window into the same shape Grid's uses, before the first frame.
///
/// On macOS the title bar is hidden and the traffic lights float over the
/// rail, which leaves room for them (see `railTopInset` in
/// `widgets/window_chrome.dart`) and doubles as the drag handle. Windows and
/// Linux keep their native caption bar: they draw no controls over a hidden
/// one, so hiding it would leave a window with no close button.
///
/// The sizes are Grid's too, so the two apps open to the same frame on a desk
/// where both are running.
Future<void> configureDesktopWindow() async {
  await windowManager.ensureInitialized();
  final options = WindowOptions(
    size: const Size(1280, 800),
    minimumSize: const Size(880, 560),
    title: 'Harness',
    center: true,
    titleBarStyle: Platform.isMacOS
        ? TitleBarStyle.hidden
        : TitleBarStyle.normal,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}
