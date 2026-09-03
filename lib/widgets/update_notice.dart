import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../state/app_state.dart';
import '../update/desktop_updater.dart';
import '../update/manual_update_check.dart';
import 'window_chrome.dart';

/// "18.4 MB" — a download the user is about to authorise, in the unit they
/// think in. Bytes are what the manifest carries; nobody reads 19293798.
String formatDownloadSize(int bytes) {
  if (bytes <= 0) return '';
  const mb = 1024 * 1024;
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  return '${(bytes / 1024).round()} KB';
}

/// The band across the top of the app when a newer build is out.
///
/// It carries three states off one flag pair on [AppNotifier]: an offer, the
/// install running, and a failed install. The failure keeps the offer alive —
/// nothing was changed on disk, so the only honest thing to show is a way to
/// try again.
class UpdateNotice extends StatelessWidget {
  final AppNotifier notifier;

  const UpdateNotice({super.key, required this.notifier});

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final update = notifier.availableUpdate;
    if (update == null) return const SizedBox.shrink();

    final installing = notifier.isInstallingUpdate;
    final error = notifier.updateError;
    final failed = error != null && !installing;

    // Amber for a failure, the accent wash otherwise. Deliberately NOT green:
    // green is "machine online" everywhere else in this window, and a second
    // meaning for it here would make the rail's dots ambiguous.
    // ⚠️ COMPOSITED OVER THE WINDOW, NOT LEFT TRANSLUCENT. Both tints below are
    // washes — 8% and 10% — and this band is the one strip of the app that does
    // NOT sit inside a Scaffold: it takes a row of its own directly under
    // MaterialApp's home, so there is no surface behind it to tint. Left as-is
    // the wash lands on the bare window, which is still the platform's dark
    // ground, and the banner stays black while the whole app around it goes
    // light. Blending against the window colour keeps the designed tint and
    // gives it something to be a tint OF.
    final wash = failed
        ? grid.AppPalette.warn.withValues(alpha: 0.10)
        : grid.AppSurface.accentWash;
    final tint = Color.alphaBlend(wash, grid.AppPalette.windowBg);
    final rule = failed
        ? grid.AppPalette.warn.withValues(alpha: 0.28)
        : grid.AppPalette.accentOnSurface.withValues(alpha: 0.24);
    final markColor = failed
        ? grid.AppPalette.warn
        : grid.AppPalette.accentOnSurface;

    final String message;
    if (failed) {
      message = error;
    } else if (installing) {
      message = 'Installing Harness ${update.version}…';
    } else {
      message = 'Harness ${update.version} is available';
    }

    return DragToMoveArea(
      child: Material(
        color: Colors.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tint,
            border: Border(bottom: BorderSide(color: rule)),
          ),
          child: Stack(
            children: [
              Padding(
                // Starts clear of the traffic lights: this band is the top edge
                // of the window when it shows, and the lights float over it.
                padding: EdgeInsets.fromLTRB(
                  14 + trafficLightClearance,
                  7,
                  10,
                  7,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: installing
                          ? CircularProgressIndicator(
                              strokeWidth: 2,
                              color: grid.AppPalette.accentOnSurface,
                            )
                          : Icon(
                              failed
                                  ? LucideIcons.triangleAlert300
                                  : LucideIcons.arrowDownToLine300,
                              size: 16,
                              color: markColor,
                            ),
                    ),
                    const SizedBox(width: 10),
                    // ONE expanding child, holding the whole message. A
                    // Flexible text beside a Spacer splits the free space
                    // between them, which leaves the actions stranded
                    // mid-band instead of anchored to the right edge.
                    //
                    // Inside it the sentence yields before the size does: a
                    // truncated sentence still leaves both readable, whereas
                    // wrapping one would push the buttons out of the band.
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              message,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: grid.AppPalette.textPrimary,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                          if (!installing && !failed && update.size > 0) ...[
                            const SizedBox(width: 8),
                            Text(
                              '· ${formatDownloadSize(update.size)}',
                              style: TextStyle(
                                color: grid.AppPalette.textFaint,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (failed) ...[
                      _NoticeAction(
                        label: 'Dismiss',
                        onPressed: notifier.dismissUpdateError,
                      ),
                      const SizedBox(width: 6),
                      _NoticeAction(
                        key: const Key('retry-update-button'),
                        label: 'Try again',
                        kind: _ActionKind.ghost,
                        onPressed: () =>
                            unawaited(notifier.installAvailableUpdate()),
                      ),
                    ] else ...[
                      _NoticeAction(
                        key: const Key('skip-update-button'),
                        label: 'Skip this version',
                        onPressed: installing
                            ? null
                            : notifier.skipAvailableUpdate,
                      ),
                      const SizedBox(width: 6),
                      _NoticeAction(
                        key: const Key('install-update-button'),
                        label: 'Update',
                        kind: _ActionKind.primary,
                        onPressed: installing
                            ? null
                            : () =>
                                  unawaited(notifier.installAvailableUpdate()),
                      ),
                    ],
                  ],
                ),
              ),
              // Indeterminate on purpose: downloadAndStage() resolves once, with
              // no byte counter to read, so a percentage here would be invented.
              if (installing)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                    color: grid.AppPalette.accentOnSurface,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen block shown instead of the rest of the app when [AppNotifier.hasForcedUpdate] is
/// true — a major/minor version bump. Unlike [UpdateNotice] and the manual-check dialog, this has
/// no skip and no close: the only way past it is a successful install, which replaces the running
/// process and never returns here.
class ForcedUpdateScreen extends StatelessWidget {
  final AppNotifier notifier;

  const ForcedUpdateScreen({super.key, required this.notifier});

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final update = notifier.availableUpdate;
    if (update == null) return const SizedBox.shrink();

    final installing = notifier.isInstallingUpdate;
    final error = notifier.updateError;
    final failed = error != null && !installing;
    final mark = failed
        ? grid.AppPalette.warn
        : grid.AppPalette.accentOnSurface;

    // Material, because this screen is handed to MaterialApp's home slot RAW while every one of its
    // siblings there brings its own — LoginScreen, HomeScreen and EnvironmentSetupScreen are Scaffolds
    // and the bootstrapping branch is literally `const Scaffold(...)`. Without one, MaterialApp falls
    // back to _errorTextStyle, whose debugLabel says the quiet part out loud: "fallback style; consider
    // putting your text in a Material".
    //
    // It did NOT look like a missing-Material error, which is why it survived: every Text here sets its
    // own colour, size and weight, so the fallback's red 48px monospace was overridden — but nothing
    // sets `decoration`, so its yellow double underline came through and read as a deliberate, baffling
    // style choice on every line. Transparent so the ColoredBox stays the ground, as UpdateNotice does.
    return ColoredBox(
      color: grid.AppPalette.windowBg,
      child: Material(
        color: Colors.transparent,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: grid.AppGlass.surfaceFill,
                borderRadius: BorderRadius.circular(grid.AppCard.radius),
                border: Border.all(color: grid.AppGlass.hair),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: mark.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: installing
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: mark,
                              ),
                            )
                          : Icon(
                              failed
                                  ? LucideIcons.triangleAlert300
                                  : LucideIcons.arrowDownToLine300,
                              size: 20,
                              color: mark,
                            ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      installing
                          ? 'Installing Harness ${update.version}…'
                          : failed
                          ? 'Update failed'
                          : 'Harness ${update.version} is required',
                      style: TextStyle(
                        color: grid.AppPalette.textPrimary,
                        fontSize: 17,
                        fontWeight: grid.AppFont.semibold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      installing
                          ? 'Don’t quit Harness. It will restart on its own.'
                          : failed
                          ? error
                          : 'This version of Harness can no longer be used. '
                                'Update to continue.',
                      style: TextStyle(
                        color: grid.AppPalette.textSecondary,
                        fontSize: 12.5,
                        height: 1.5,
                      ),
                    ),
                    if (!installing) ...[
                      const SizedBox(height: 14),
                      Divider(height: 1, color: grid.AppGlass.hair),
                      const SizedBox(height: 10),
                      _Fact(label: 'Installed', value: _InstalledVersion()),
                      const SizedBox(height: 6),
                      _Fact(label: 'New version', value: Text(update.version)),
                      if (update.size > 0) ...[
                        const SizedBox(height: 6),
                        _Fact(
                          label: 'Download',
                          value: Text(formatDownloadSize(update.size)),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _NoticeAction(
                            key: const Key('forced-update-install-button'),
                            label: failed ? 'Try again' : 'Update now',
                            kind: _ActionKind.primary,
                            onPressed: () =>
                                unawaited(notifier.installAvailableUpdate()),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _ActionKind { quiet, ghost, primary }

class _NoticeAction extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final _ActionKind kind;

  const _NoticeAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = _ActionKind.quiet,
  });

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final primary = kind == _ActionKind.primary;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 26),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
        backgroundColor: primary
            ? grid.AppPalette.accentOnSurface
            : Colors.transparent,
        foregroundColor: primary
            ? grid.AppPalette.windowBg
            : grid.AppPalette.textSecondary,
        disabledForegroundColor: grid.AppPalette.textFaint,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(7),
          side: kind == _ActionKind.ghost
              ? BorderSide(color: grid.AppGlass.hair)
              : BorderSide.none,
        ),
        textStyle: TextStyle(
          fontSize: 12,
          fontWeight: primary ? grid.AppFont.semibold : grid.AppFont.regular,
        ),
      ),
      child: Text(label),
    );
  }
}

/// Opens the result of a manual check from the Harness menu. It never downloads
/// a release until the user chooses the primary action.
Future<void> showUpdateCheckDialog(
  BuildContext context,
  AppNotifier notifier,
  ManualUpdateCheck result,
) {
  final update = result.update;
  if (update == null) {
    return showDialog<void>(
      context: context,
      builder: (context) => const _UpdateDialog(
        icon: LucideIcons.circleCheck300,
        tone: _DialogTone.ok,
        title: 'You’re up to date',
        body: 'This copy of Harness already has the latest version.',
      ),
    );
  }
  if (update.forced) {
    // A forced update is never offered as a dialog the user could otherwise close or skip —
    // `notifier.checkForUpdates()` (awaited by every caller before this runs) already set
    // `availableUpdate`, which flips `RootShell` to the blocking `ForcedUpdateScreen`. That's
    // already on screen by now; a second, competing "here's your only way out" modal on top of it
    // would just be a redundant, harder-to-get-right copy of the same no-escape state machine.
    return Future.value();
  }
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      var installing = false;
      return StatefulBuilder(
        builder: (context, setState) => _UpdateDialog(
          icon: LucideIcons.arrowDownToLine300,
          title: installing
              ? 'Installing Harness ${update.version}…'
              : 'Harness ${update.version} is available',
          body: installing
              ? 'Don’t quit Harness. It will restart on its own.'
              : result.isSkipped
              ? 'You skipped this version earlier. You can still install it.'
              : 'Download and install it now? Harness will restart when it '
                    'finishes.',
          busy: installing,
          update: installing ? null : update,
          actions: installing
              ? const []
              : [
                  _DialogAction(
                    key: const Key('close-update-dialog-button'),
                    label: 'Close',
                    onPressed: () async {
                      Navigator.of(dialogContext).pop();
                    },
                  ),
                  _DialogAction(
                    label: result.isSkipped
                        ? 'Not now'
                        : 'Skip ${update.version}',
                    onPressed: () async {
                      if (!result.isSkipped) {
                        await notifier.skipAvailableUpdate();
                      }
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                    },
                  ),
                  _DialogAction(
                    label: 'Update',
                    primary: true,
                    onPressed: () async {
                      setState(() => installing = true);
                      final installed = await notifier.installAvailableUpdate();
                      // A successful install never returns — the process is
                      // replaced. Reaching here means it failed, and the banner
                      // behind this dialog is already showing why.
                      if (!dialogContext.mounted || installed) return;
                      Navigator.of(dialogContext).pop();
                    },
                  ),
                ],
        ),
      );
    },
  );
}

enum _DialogTone { accent, ok }

class _DialogAction {
  final Key? key;
  final String label;
  final bool primary;
  final Future<void> Function() onPressed;

  const _DialogAction({
    this.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });
}

class _UpdateDialog extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final _DialogTone tone;
  final bool busy;
  final UpdateInfo? update;
  final List<_DialogAction> actions;

  const _UpdateDialog({
    required this.icon,
    required this.title,
    required this.body,
    this.tone = _DialogTone.accent,
    this.busy = false,
    this.update,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final mark = tone == _DialogTone.ok
        ? grid.AppPalette.online
        : grid.AppPalette.accentOnSurface;

    return Dialog(
      // No backgroundColor, no shape: `dialogTheme` supplies both, at
      // AppGlass.surfaceFill and AppCard.radius (12). The rim this used to
      // carry is gone with them — §1 allows exactly one border in the app and
      // it belongs to the menu panel, not to a dialog.
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 372),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: mark.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(grid.AppCard.insetRadius),
                ),
                alignment: Alignment.center,
                child: busy
                    ? SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: mark,
                        ),
                      )
                    : Icon(icon, size: 18, color: mark),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  color: grid.AppPalette.textPrimary,
                  fontSize: 15,
                  fontWeight: grid.AppFont.semibold,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                body,
                style: TextStyle(
                  color: grid.AppPalette.textSecondary,
                  fontSize: 12.5,
                  height: 1.5,
                ),
              ),
              if (update != null) ...[
                const SizedBox(height: 12),
                Divider(height: 1, color: grid.AppGlass.hair),
                const SizedBox(height: 10),
                _Fact(label: 'Installed', value: _InstalledVersion()),
                const SizedBox(height: 6),
                _Fact(label: 'New version', value: Text(update!.version)),
                if (update!.size > 0) ...[
                  const SizedBox(height: 6),
                  _Fact(
                    label: 'Download',
                    value: Text(formatDownloadSize(update!.size)),
                  ),
                ],
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (final action in actions) ...[
                      if (action != actions.first) const SizedBox(width: 8),
                      _NoticeAction(
                        key: action.key,
                        label: action.label,
                        kind: action.primary
                            ? _ActionKind.primary
                            : _ActionKind.quiet,
                        onPressed: () => unawaited(action.onPressed()),
                      ),
                    ],
                  ],
                ),
              ],
              if (actions.isEmpty && !busy) ...[
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _NoticeAction(
                      label: 'Close',
                      kind: _ActionKind.ghost,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One `label · value` line in the dialog's fact block.
class _Fact extends StatelessWidget {
  final String label;
  final Widget value;

  const _Fact({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: TextStyle(color: grid.AppPalette.textFaint, fontSize: 11.5),
          ),
        ),
        DefaultTextStyle(
          style: TextStyle(
            color: grid.AppPalette.textSecondary,
            fontSize: 11.5,
            fontFamily: grid.AppFont.mono,
            fontFamilyFallback: grid.AppFont.monoFallback,
          ),
          child: value,
        ),
      ],
    );
  }
}

class _InstalledVersion extends StatelessWidget {
  @override
  Widget build(BuildContext context) => FutureBuilder<PackageInfo>(
    future: PackageInfo.fromPlatform(),
    builder: (context, snapshot) => Text(snapshot.data?.version ?? '—'),
  );
}
