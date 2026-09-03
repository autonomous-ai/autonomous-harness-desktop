import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/widgets/section_scaffold.dart';
import '../../state/app_state.dart';
import '../../widgets/update_notice.dart';

/// Settings ▸ About: which build this is, and the way to ask for a newer one.
///
/// The check runs through [AppNotifier.checkForUpdates] and reports through
/// [showUpdateCheckDialog] — the same pair the "Check for Updates…" menu item
/// drives, so the menu and this button can't answer differently.
class AboutSection extends StatefulWidget {
  const AboutSection({super.key, required this.notifier});

  final AppNotifier notifier;

  @override
  State<AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<AboutSection> {
  /// Held here rather than on [AppNotifier]: a check started from this button
  /// is this screen's business, and the notifier already carries the state that
  /// outlives it (the update found, the install running, the error).
  bool _checking = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      final result = await widget.notifier.checkForUpdates();
      if (!mounted) return;
      await showUpdateCheckDialog(context, widget.notifier, result);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return SectionScaffold(
      title: 'About',
      subtitle:
          'Harness Desktop attaches terminals to the agents running on your '
          'machines. It updates itself — this is where you can ask early.',
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _VersionRow(),
              const SizedBox(height: 18),
              FilledButton(
                key: const Key('settings-check-updates-button'),
                onPressed: _checking ? null : _check,
                child: Text(_checking ? 'Checking…' : 'Check for updates'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Version 1.0.4", read from the bundle rather than from any file in this
/// repo — `pubspec.yaml`'s version is a placeholder the release never touches
/// (see RELEASE.md).
class _VersionRow extends StatelessWidget {
  const _VersionRow();

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) => Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              'Version',
              style: TextStyle(
                color: grid.AppPalette.textFaint,
                fontSize: 12.5,
              ),
            ),
          ),
          Text(
            snapshot.data?.version ?? '—',
            style: TextStyle(
              color: grid.AppPalette.textPrimary,
              fontSize: 12.5,
              fontFamily: grid.AppFont.mono,
              fontFamilyFallback: grid.AppFont.monoFallback,
            ),
          ),
        ],
      ),
    );
  }
}
