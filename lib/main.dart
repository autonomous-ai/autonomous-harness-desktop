import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/crash_log.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'state/app_state.dart';
import 'shared/theme/app_theme.dart' as grid;
import 'shared/theme/theme_mode_store.dart';
import 'terminal/terminal_font_store.dart';
import 'theme/app_theme.dart';
import 'widgets/awaiting_browser_login_screen.dart';
import 'widgets/environment_setup_screen.dart';
import 'widgets/flash_firmware_dialog.dart';
import 'core/startup.dart';
import 'widgets/shortcuts_sheet.dart';
import 'widgets/update_notice.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Before anything else can fail.
  CrashLog.install();
  await loadPersistedSettings();
  runApp(const ProviderScope(child: DesktopApp()));
}

class DesktopApp extends StatelessWidget {
  const DesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilds MaterialApp on a theme change, which is what re-resolves both
    // ThemeData objects and, through the scope below, every Grid token with them.
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeStore,
      builder: (context, mode, _) => _app(mode),
    );
  }

  Widget _app(ThemeMode mode) {
    return MaterialApp(
      title: 'Harness',
      // Both shells are built from the SAME chrome against different palettes —
      // see AppTheme.terminal. Passing terminalDark twice, as this did, is why a
      // light palette that had been written in full could never be worn: nothing
      // in the app was ever asked for it.
      theme: AppTheme.terminalLight,
      darkTheme: AppTheme.terminalDark,
      themeMode: mode,
      // Publishes the brightness Grid's tokens resolve against, and marks every
      // widget that reads one dirty when it changes.
      //
      // It has to sit inside `builder` rather than above MaterialApp: only here
      // is there a Theme to read. Without it the tokens default to their light
      // values and the rail would paint white inside a dark window.
      builder: (context, child) =>
          _GridTokenScope(child: child ?? const SizedBox.shrink()),
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
            Expanded(child: screen),
          ],
        );
      },
    );
  }
}
