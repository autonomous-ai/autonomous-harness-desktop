import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';

import '../stats/harness_stats.dart';
import 'analytics.dart';

/// Closes the launch out: `app_closed`, then a time-boxed drain of whatever is
/// still queued. Renders [child] unchanged.
///
/// Only `didRequestAppExit` is hooked, which covers ⌘Q, the app menu's Quit and
/// an OS log-out. Grid also intercepts the window's close button, but that
/// needs `windowManager.setPreventClose(true)` and a matching `destroy()` call
/// — and a bug on that path leaves a window the user cannot close. A missing
/// `app_closed` is worth less than that risk, so this app takes the exit hook
/// alone; `app_opened` is unaffected either way.
///
/// The matching `app_opened` is NOT here. It is sent by `AppNotifier` when
/// bootstrap resolves, because `signed_in` is not known until the CLI has been
/// asked, and a first-frame event would report every launch as signed out.
class AnalyticsLifecycle extends StatefulWidget {
  const AnalyticsLifecycle({super.key, required this.child});

  final Widget child;

  @override
  State<AnalyticsLifecycle> createState() => _AnalyticsLifecycleState();
}

class _AnalyticsLifecycleState extends State<AnalyticsLifecycle>
    with WidgetsBindingObserver {
  /// When this launch started, so the quit event can say how long the app was
  /// open.
  final DateTime _openedAt = DateTime.now();

  /// Guards against a quit that somehow asks twice.
  bool _closed = false;

  /// Time this window has actually been in front of somebody.
  ///
  /// Accumulated across resumes rather than measured once, because the thing
  /// being counted is interrupted by definition: a person switches to a browser
  /// and back a dozen times an hour, and only the sum of the front-most spells
  /// is "how long they used it".
  Duration _focused = Duration.zero;
  DateTime? _frontSince;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The app is in front when it launches. Without this the first spell — very
    // often the longest — would not be counted at all.
    _frontSince = DateTime.now();
  }

  /// macOS sends `inactive` when the window loses key, `resumed` when it gets it
  /// back. `hidden` and `paused` arrive on the way out of sight; all three are
  /// the same fact for this purpose — not in front any more.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _frontSince ??= DateTime.now();
      return;
    }
    final since = _frontSince;
    if (since != null) {
      _focused += DateTime.now().difference(since);
      _frontSince = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    if (!_closed) {
      _closed = true;
      final now = DateTime.now();
      final since = _frontSince;
      if (since != null) _focused += now.difference(since);
      analytics.appClosed(open: now.difference(_openedAt));
      // Beside it, not instead of it: `app_closed` says how long the window was
      // there, this says how much of that a person was actually looking at, and
      // the pair is the only honest reading for an app people leave open.
      analytics.appFocusTime(
        open: now.difference(_openedAt),
        focused: _focused,
      );
      // Before the drain below, and awaited: this is a local file write that
      // finishes in milliseconds, and it is the ONLY place a turn still running
      // at quit gets its time counted — the debounce timer is cancelled by the
      // process exiting, not fired by it.
      await harnessStats.flush();
      // Time-boxed inside `close` itself — a wedged network must never be what
      // keeps the window on screen after the user pressed ⌘Q.
      await analytics.close();
    }
    return AppExitResponse.exit;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
