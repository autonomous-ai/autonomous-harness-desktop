import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/crash_log.dart';
import 'core/desktop_window.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'state/app_state.dart';
import 'shared/theme/app_theme.dart' as grid;
import 'shared/theme/appearance_prefs_store.dart';
import 'shared/theme/theme_mode_store.dart';
import 'terminal/terminal_font_store.dart';
import 'widgets/awaiting_browser_login_screen.dart';
import 'widgets/environment_setup_screen.dart';
import 'widgets/flash_firmware_dialog.dart';
import 'core/startup.dart';
import 'widgets/shortcuts_sheet.dart';
import 'widgets/update_notice.dart';
import 'widgets/window_chrome.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Before anything else can fail.
  CrashLog.install();
  await loadPersistedSettings();
  // After the settings: the window shows itself once it is ready, and the
  // first frame it shows must already wear the saved theme.
  await configureDesktopWindow();
  runApp(const ProviderScope(child: DesktopApp()));
}

class DesktopApp extends StatelessWidget {
  const DesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilds MaterialApp on a theme change, which is what re-resolves both
    // ThemeData objects and, through the scope below, every Grid token with them.
    //
    // The type settings need the same treatment for a different reason:
    // `buildAppTheme` bakes `AppControl.*Scaled` into plain numbers at the
    // moment it runs, so a UI size that changed without rebuilding this would
    // repaint nothing at all.
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeStore,
      builder: (context, mode, _) => ValueListenableBuilder<AppearancePrefs>(
        valueListenable: appearancePrefsStore,
        builder: (context, prefs, _) => _app(mode, prefs),
      ),
    );
  }

  Widget _app(ThemeMode mode, AppearancePrefs prefs) {
    // ⚠️ ORDER MATTERS, and it is why this is a statement rather than something
    // tucked into the tree below: `buildAppTheme` reads `AppFont.sans` and
    // `AppControl.*Scaled`, so the settings have to be on `AppFont` BEFORE the
    // theme is built, in this same frame.
    //
    // Pushed through the notifier rather than calling `AppFont.apply` directly,
    // so widgets past a `const` boundary — which a top-down rebuild never
    // reaches — are marked dirty too.
    //
    // `codeSize` is passed through unchanged: code type is not on this screen
    // yet, and `apply` takes the whole set, so reading the current value back is
    // how "leave it alone" is spelled.
    final scale = prefs.uiSize / grid.AppFont.uiSizeDefault;
    grid.AppTheme.fonts.apply(
      uiFamily: prefs.uiFamily,
      uiScale: scale,
      codeSize: grid.AppFont.codeSize,
    );
    return MaterialApp(
      title: 'Harness',
      // Both shells are built from the SAME function against different
      // palettes, so the two can never drift apart.
      //
      // ⚠️ This is the design system's own `buildAppTheme`, and until now it was
      // NOT what the app wore — these two lines named a second, hand-written
      // ThemeData that shadowed it, which is why the type ramp, `AppControl`,
      // `AppMenu` and `trackingFor` rendered nothing at runtime. See the note
      // where that theme used to live, in `lib/theme/app_theme.dart`.
      theme: grid.buildAppTheme(brightness: Brightness.light),
      darkTheme: grid.buildAppTheme(brightness: Brightness.dark),
      themeMode: mode,
      // Publishes the brightness Grid's tokens resolve against, and marks every
      // widget that reads one dirty when it changes.
      //
      // It has to sit inside `builder` rather than above MaterialApp: only here
      // is there a Theme to read. Without it the tokens default to their light
      // values and the rail would paint white inside a dark window.
      // The UI size reaches every `Text` as a text SCALE rather than as hundreds
      // of edited call sites. `withClampedTextScaling` with both bounds equal IS
      // the way to force a factor — MediaQuery has no "set the scale"
      // constructor that still inherits the platform's other metrics.
      //
      // ⚠️ It is a matched pair with the `AppControl.*Scaled` reads above, not a
      // separate nicety: those grow the BOXES and this grows the TYPE, and
      // `AppControl.fontSize` deliberately has no scaled twin so that the factor
      // is applied exactly once. Ship one without the other and a 19px setting
      // gives 19px-tall buttons wrapped around 13pt labels.
      //
      // ⚠️ The terminal is fenced out of this at five seams — see
      // `terminal_panel.dart`, `terminal_composer.dart`, `engine_identity.dart`
      // and `terminal_section.dart`, and the regression test in
      // `test/terminal_ui_scale_isolation_test.dart`. The terminal keeps its own
      // font settings because its type is a grid a remote program draws into.
      //
      // Outermost inside `builder`, with `_GridTokenScope` inside it: the clamp
      // has to be an ancestor of everything that lays out text, while the scope
      // only reads `Theme.of`, which comes from above the builder either way.
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: scale,
        maxScaleFactor: scale,
        child: _GridTokenScope(child: child ?? const SizedBox.shrink()),
      ),
      home: const RootShell(),
    );
  }
}

/// Carries Grid's design tokens past this app's `const` chrome.
///
/// A `const` widget is reference-identical across its parent's rebuild, so a
/// top-down rebuild never reaches one — it would keep the palette it first
/// mounted with. [grid.BrightnessScope] marks the ones that called
/// `AppTheme.watch` dirty directly, across that boundary.
class _GridTokenScope extends StatelessWidget {
  const _GridTokenScope({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.brightness.value = Theme.of(context).brightness;
    return grid.BrightnessScope(child: child);
  }
}

/// Carries "Check for Updates…" from the macOS application menu into Dart.
///
/// The item is installed natively (MainFlutterWindow.swift) so the rest of the
/// menu bar keeps coming from the nib; all this side does is act on the tap.
const _appMenuChannel = MethodChannel('harness/app_menu');

class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key});

  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell> {
  @override
  void initState() {
    super.initState();
    _appMenuChannel.setMethodCallHandler(_onAppMenu);
  }

  @override
  void dispose() {
    _appMenuChannel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _onAppMenu(MethodCall call) async {
    switch (call.method) {
      case 'checkForUpdates':
        final app = ref.read(appStateProvider);
        final result = await app.checkForUpdates();
        if (!mounted) return;
        await showUpdateCheckDialog(context, app, result);
      case 'flashFirmware':
        await showFlashFirmwareDialog(context);
      case 'showShortcuts':
        await showShortcutsSheet(context);
      case 'increaseTerminalFontSize':
        await terminalFontStore.increaseSize();
      case 'decreaseTerminalFontSize':
        await terminalFontStore.decreaseSize();
      case 'resetTerminalFontSize':
        await terminalFontStore.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final Widget screen;
        // A forced (major/minor) update wins over every other status, including the login screen —
        // this build can no longer be used at all, so there is nothing underneath worth showing.
        if (app.hasForcedUpdate) {
          screen = ForcedUpdateScreen(notifier: app);
        } else {
          switch (app.status) {
            case AppStatus.bootstrapping:
              screen = app.pendingAuthorizeUrl != null
                  ? AwaitingBrowserLoginScreen(onCancel: app.cancelLogin)
                  : const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
            case AppStatus.preparingEnvironment:
              screen = EnvironmentSetupScreen(notifier: app);
            case AppStatus.unauthenticated:
              screen = LoginScreen(notifier: app);
            case AppStatus.authenticated:
              screen = HomeScreen(notifier: app);
          }
        }
        // Only the home shell carries its own drag handle and traffic-light
        // clearance (the rail's head). Every other screen fills the window
        // with a centred card, so the strip goes over it here, once, instead
        // of inside each of them.
        final framed =
            app.status == AppStatus.authenticated && !app.hasForcedUpdate
            ? screen
            : FullWindowScreen(child: screen);
        // The band takes a row of its own rather than floating over one. As an
        // overlay it landed on the rail's head — covering the wordmark and the
        // three buttons beside it, which is the one strip of this window that
        // must stay reachable.
        return Column(
          children: [
            if (app.hasAvailableUpdate &&
                !app.hasForcedUpdate &&
                app.status != AppStatus.bootstrapping &&
                app.status != AppStatus.preparingEnvironment)
              UpdateNotice(notifier: app),
            Expanded(child: framed),
          ],
        );
      },
    );
  }
}
