import 'package:flutter/material.dart';

import '../grid/grid_networks_controller.dart';
import '../shared/theme/app_theme.dart' as grid;
import '../state/app_state.dart';
import '../widgets/window_chrome.dart';
import 'sections/about_section.dart';
import 'sections/appearance_section.dart';
import 'sections/grid_section.dart';
import 'sections/share_intelligence_section.dart';
import 'sections/shortcuts_section.dart';
import 'sections/terminal_section.dart';
import 'settings_nav.dart';
import 'settings_section.dart';

/// Opens Settings over the app.
///
/// A screen, not a dialog: the sections outgrew a 360px box the moment there
/// was more than one of them, and a settings *place* is what every desktop app
/// this one sits beside offers. It takes the whole window for the same reason
/// Grid's does — none of this is daily work, so it does not belong in the rail
/// you drive terminals from.
///
/// Pushed as a route rather than switched into the shell: [AppNotifier] carries
/// no notion of "which screen", and a route needs none — the way back is
/// [Navigator.pop], and the shell underneath keeps its panes attached and its
/// terminals streaming while this is up.
Future<void> showSettingsScreen(
  BuildContext context,
  AppNotifier notifier, {
  GridNetworksController? gridNetworks,
  SettingsSection? initialSection,
}) {
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      // Opaque: it covers the window, and letting the shell show through would
      // mean compositing four live terminals under it for nothing.
      pageBuilder: (context, animation, _) => SettingsScreen(
        notifier: notifier,
        gridNetworks: gridNetworks,
        initialSection: initialSection,
      ),
      transitionsBuilder: (context, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
      // A cross-fade, not a slide. A screen that slides in from the right reads
      // as a phone pushing a detail view; Settings arriving in place reads as
      // the window changing what it is showing.
      transitionDuration: const Duration(milliseconds: 170),
      reverseTransitionDuration: const Duration(milliseconds: 120),
    ),
  );
}

/// Settings: pick on the left, work on the right.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.notifier,
    this.gridNetworks,
    this.initialSection,
  });

  final AppNotifier notifier;

  /// Which row Settings opens on. Null takes [kDefaultSettingsSection] — the
  /// first row of the first group, so the screen never opens on a pane its rail
  /// does not show as selected.
  final SettingsSection? initialSection;

  /// Injected by tests so the Grid pane reads a fake client instead of the
  /// live control plane. Null in the app, where the screen makes — and
  /// disposes — its own.
  final GridNetworksController? gridNetworks;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late SettingsSection _section =
      widget.initialSection ?? kDefaultSettingsSection;

  /// Owned here, not by the Grid pane: the rail unmounts a pane the moment you
  /// leave it, so a controller living in the pane would refetch every time the
  /// user came back to it.
  late final GridNetworksController _gridNetworks =
      widget.gridNetworks ?? GridNetworksController();

  @override
  void dispose() {
    // Only the one this screen made — an injected controller belongs to whoever
    // passed it in.
    if (widget.gridNetworks == null) _gridNetworks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    // Row-first, so the nav rail owns the window's full height and its fill
    // runs from y=0 — under the macOS traffic lights included. A header across
    // the top would have to carry the rail's fill over the pane as well, which
    // is what leaves the top of a window reading as a separate, lighter band.
    return Scaffold(
      backgroundColor: grid.AppPalette.windowBg,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsNav(
            section: _section,
            onSelect: (target) => setState(() => _section = target),
          ),
          VerticalDivider(width: 1, color: grid.AppPalette.divider),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The pane needs the traffic lights' clearance and somewhere to
                // grab the window, but no fill of its own — it sits on the
                // window. The rail draws its own.
                const WindowDragStrip(),
                Expanded(
                  child: _SettingsBody(
                    section: _section,
                    notifier: widget.notifier,
                    gridNetworks: _gridNetworks,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The screen behind a [SettingsSection].
///
/// Cross-fades rather than cuts: the rail's own row highlight animates, and a
/// pane that appears the instant you click reads as a jolt beside it.
class _SettingsBody extends StatelessWidget {
  const _SettingsBody({
    required this.section,
    required this.notifier,
    required this.gridNetworks,
  });

  final SettingsSection section;
  final AppNotifier notifier;
  final GridNetworksController gridNetworks;

  @override
  Widget build(BuildContext context) {
    final screen = switch (section) {
      SettingsSection.grid => GridSection(controller: gridNetworks),
      SettingsSection.shareIntelligence => const ShareIntelligenceSection(),
      SettingsSection.appearance => const AppearanceSection(),
      SettingsSection.terminal => const TerminalSection(),
      SettingsSection.shortcuts => const ShortcutsSection(),
      SettingsSection.about => AboutSection(notifier: notifier),
    };
    return AnimatedSwitcher(
      // The exit is the shorter half — waiting on it is what makes a cross-fade
      // feel sluggish.
      duration: const Duration(milliseconds: 200),
      reverseDuration: const Duration(milliseconds: 90),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      // Keyed by section, not by widget type: that is what tells the switcher a
      // *different screen* arrived.
      child: KeyedSubtree(key: ValueKey(section), child: screen),
    );
  }
}
