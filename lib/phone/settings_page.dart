import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/app_version.dart';
import '../shared/theme/app_theme.dart';
import '../shared/theme/appearance_prefs_store.dart';
import '../state/app_state.dart';
import '../terminal/terminal_font_store.dart';
import 'phone_header.dart';
import 'phone_sheet.dart';
import 'settings_row.dart';

/// The phone's Settings tab.
///
/// DELIBERATELY not the desktop's eight sections. Four of them cannot work in a viewer build and
/// would each be a screen that opens on nothing:
///
///  - **Usage** reads `~/.claude/projects`, `~/.codex` and OpenCode's SQLite file ON THIS DISK. A
///    phone has none of them — every figure would be zero, for agents that really are running.
///  - **Autonomous devices** flashes an ESP32 over a serial port, through the CLI. A viewer has no
///    CLI and a phone has no serial port.
///  - **Keyboard shortcuts** is a list of ⌘ combinations for a keyboard that is not there.
///  - **Check for updates** belongs to the desktop updater; a phone build is updated by its store.
///
/// What a phone adds instead is the account and the machine links, which the desktop keeps in its
/// rail footer — on a phone there is no rail, so this is the only way to reach either.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.notifier});

  final AppNotifier notifier;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: notifier,
    builder: (context, _) {
      AppTheme.watch(context);
      return Scaffold(
        backgroundColor: AppPalette.windowBg,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const PhoneHeader(large: true, title: 'Settings'),
              Expanded(child: _Body(notifier: notifier)),
            ],
          ),
        ),
      );
    },
  );
}

class _Body extends StatelessWidget {
  const _Body({required this.notifier});

  final AppNotifier notifier;

  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.fromLTRB(
      16,
      // Zero: the first caption brings its own 22pt top, and any padding here would stack on it —
      // the gap under the big "Settings" title would then be a header gap plus a between-groups
      // gap, wider than every other gap on the screen.
      0,
      16,
      MediaQuery.paddingOf(context).bottom + 24,
    ),
    children: [
      const SettingsCaption('Account'),
      SettingsGroup(
        children: [
          SettingsRow(
            leading: _Avatar(notifier: notifier),
            title: notifier.currentUser?.displayName ?? 'Signed in',
            detail: notifier.currentUser?.email,
            onTap: () => _showAccountSheet(context, notifier),
          ),
        ],
      ),
      const SettingsCaption('Terminal'),
      SettingsGroup(children: [_FontRow(), _SizeRow()]),
      const SettingsCaption('Appearance'),
      SettingsGroup(children: [_TextSizeRow()]),
      const SettingsNote('Harness is dark-only, so there is no theme to pick.'),
      const SettingsCaption('About'),
      SettingsGroup(children: [const _VersionRow()]),
    ],
  );

  void _showAccountSheet(BuildContext context, AppNotifier notifier) {
    showPhoneSheet(
      context,
      title: notifier.currentUser?.email ?? 'Signed in',
      actions: [
        PhoneSheetAction(
          icon: LucideIcons.logOut300,
          label: 'Sign out',
          destructive: true,
          onTap: () => unawaited(notifier.logout()),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.notifier});

  final AppNotifier notifier;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final user = notifier.currentUser;
    final source = (user?.name?.trim().isNotEmpty ?? false)
        ? user!.name!.trim()
        : (user?.email ?? '');
    final initial = source.isEmpty ? '?' : source.substring(0, 1).toUpperCase();
    return Container(
      // 34, matching the stepper beside it two rows down: both are the tallest thing in their row,
      // and at 38 this one alone pushed its row past [kSettingsRowHeight] while the others sat on
      // it — one card with a taller first row.
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: AppPalette.avatarFill,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          // Scaled with the disc: 15pt inside 34 left almost no ring around the letter, which
          // reads as a cramped badge rather than an avatar.
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// The terminal typeface. A sheet rather than a dropdown: a phone has room for the whole list.
class _FontRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: terminalFontStore,
    builder: (context, _, _) {
      AppTheme.watch(context);
      return SettingsRow(
        title: 'Font',
        value: terminalFontStore.family.label,
        onTap: () => showPhoneSheet(
          context,
          title: 'Terminal font',
          actions: [
            for (final choice in TerminalFontChoice.available)
              PhoneSheetAction(
                icon: choice == terminalFontStore.family
                    ? LucideIcons.check300
                    : LucideIcons.type300,
                label: choice.label,
                onTap: () => unawaited(terminalFontStore.setFamily(choice)),
              ),
          ],
        ),
      );
    },
  );
}

/// Terminal text size, as a stepper rather than buried a screen deeper: on a phone this is the
/// setting people actually reach for, because the same pane that reads fine indoors is unreadable
/// at arm's length on a train.
class _SizeRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: terminalFontStore,
    builder: (context, _, _) {
      AppTheme.watch(context);
      final size = terminalFontStore.size;
      return SettingsRow(
        title: 'Size',
        trailing: SettingsStepper(
          value: size.toStringAsFixed(0),
          // The bounds are the store's own, so a lit + that does nothing is impossible.
          onDecrease: size > TerminalFontStore.minSize
              ? () => unawaited(terminalFontStore.decreaseSize())
              : null,
          onIncrease: size < TerminalFontStore.maxSize
              ? () => unawaited(terminalFontStore.increaseSize())
              : null,
        ),
      );
    },
  );
}

/// The app's own text size — everything that is not the terminal.
class _TextSizeRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: appearancePrefsStore,
    builder: (context, prefs, _) {
      AppTheme.watch(context);
      final size = prefs.uiSize;
      return SettingsRow(
        title: 'Text size',
        trailing: SettingsStepper(
          value: size.toStringAsFixed(0),
          onDecrease: size > AppearancePrefs.uiSizeMin
              ? () => unawaited(appearancePrefsStore.setUiSize(size - 1))
              : null,
          onIncrease: size < AppearancePrefs.uiSizeMax
              ? () => unawaited(appearancePrefsStore.setUiSize(size + 1))
              : null,
        ),
      );
    },
  );
}

/// The version, read from the bundle rather than from `pubspec.yaml` — see [appVersion].
class _VersionRow extends StatelessWidget {
  const _VersionRow();

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: runningAppVersion(),
    builder: (context, snapshot) {
      AppTheme.watch(context);
      return SettingsRow(title: 'Version', value: snapshot.data ?? '—');
    },
  );
}
