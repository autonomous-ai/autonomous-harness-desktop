import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Every keyboard shortcut in the app, declared once.
///
/// One list feeds both the live bindings and the ⌘/ sheet, so a shortcut can
/// never work without being documented or be documented without working.
///
/// ## Why every one of these is ⌘, and none is Ctrl
///
/// The main pane is a real terminal running a real TUI, and three layers below
/// this app are already holding keys:
///
/// * **The engine's TUI** — `Esc` interrupts, `⇧Tab` cycles permission modes,
///   `⌥⏎` inserts a newline.
/// * **tmux** — agents are attached to tmux panes, whose default prefix is
///   `Ctrl+B`.
/// * **The shell** — `Ctrl+C`, `Ctrl+D`, `Ctrl+R`, `Ctrl+A`, `Ctrl+E`, `Ctrl+L`.
///
/// On macOS the Command key never reaches the pty, so it is the only modifier
/// this app can spend. `⌥` is NOT available: terminals send it as a Meta/ESC
/// prefix, which is why `⌥⏎` reaches the engine at all. `⌘⌥` together is safe.
///
/// Claude Code Desktop binds `Ctrl+Tab`, ``Ctrl+` `` and `Ctrl+O`. It can — its
/// main pane is a chat. Copying that here would break the terminal, so this
/// list deliberately diverges.
///
/// Three more keys are spoken for by `package:xterm` itself on macOS — `⌘C`,
/// `⌘V`, `⌘A` (copy, paste, select all) — and must stay with it.
enum ShortcutAction {
  toggleRail,
  filterAgents,
  nextAgent,
  previousAgent,
  focusPreviousPane,
  focusNextPane,
  closePane,
  newAgent,
  reload,
  showShortcuts,
}

enum ShortcutGroup { navigate, panes, actions }

extension ShortcutGroupLabel on ShortcutGroup {
  String get label => switch (this) {
    ShortcutGroup.navigate => 'Navigate',
    ShortcutGroup.panes => 'Panes',
    ShortcutGroup.actions => 'Actions',
  };
}

class AppShortcut {
  const AppShortcut({
    required this.action,
    required this.activator,
    required this.label,
    required this.group,
  });

  final ShortcutAction action;
  final SingleActivator activator;
  final String label;
  final ShortcutGroup group;
}

const List<AppShortcut> kAppShortcuts = [
  // --- navigate -------------------------------------------------------------
  AppShortcut(
    action: ShortcutAction.nextAgent,
    // The macOS convention for "next tab" (Safari, Chrome, Finder). NOT
    // Ctrl+Tab, which tmux and the shell can both see.
    activator: SingleActivator(
      LogicalKeyboardKey.bracketRight,
      meta: true,
      shift: true,
    ),
    label: 'Next agent',
    group: ShortcutGroup.navigate,
  ),
  AppShortcut(
    action: ShortcutAction.previousAgent,
    activator: SingleActivator(
      LogicalKeyboardKey.bracketLeft,
      meta: true,
      shift: true,
    ),
    label: 'Previous agent',
    group: ShortcutGroup.navigate,
  ),
  AppShortcut(
    action: ShortcutAction.filterAgents,
    // "Find" — the rail already has the field, it just had no key.
    activator: SingleActivator(LogicalKeyboardKey.keyF, meta: true),
    label: 'Filter machines and agents',
    group: ShortcutGroup.navigate,
  ),
  AppShortcut(
    action: ShortcutAction.toggleRail,
    activator: SingleActivator(LogicalKeyboardKey.backslash, meta: true),
    label: 'Show or hide the sidebar',
    group: ShortcutGroup.navigate,
  ),

  // --- panes ----------------------------------------------------------------
  // Brackets, not arrows. Measured: xterm turns every arrow into a terminal
  // key and answers `handled`, so `⌘←`/`⌘⌥→` never reach a binding — they go
  // to the agent as cursor movement. `⌘⇧→` happens to survive today, but only
  // because of how xterm treats shift, which is not a promise to build on.
  //
  // The pairing is deliberate: the same bracket moves you between PANES, and
  // with shift between AGENTS — one key, shift widens the scope.
  AppShortcut(
    action: ShortcutAction.focusPreviousPane,
    activator: SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true),
    label: 'Focus the previous pane',
    group: ShortcutGroup.panes,
  ),
  AppShortcut(
    action: ShortcutAction.focusNextPane,
    activator: SingleActivator(LogicalKeyboardKey.bracketRight, meta: true),
    label: 'Focus the next pane',
    group: ShortcutGroup.panes,
  ),
  AppShortcut(
    action: ShortcutAction.closePane,
    // Close the pane, and — when the last one is gone — the window, which is
    // what ⌘W means everywhere else on this OS.
    activator: SingleActivator(LogicalKeyboardKey.keyW, meta: true),
    label: 'Close the focused pane',
    group: ShortcutGroup.panes,
  ),

  // --- actions --------------------------------------------------------------
  AppShortcut(
    action: ShortcutAction.newAgent,
    activator: SingleActivator(LogicalKeyboardKey.keyN, meta: true),
    label: 'New agent',
    group: ShortcutGroup.actions,
  ),
  AppShortcut(
    action: ShortcutAction.reload,
    activator: SingleActivator(LogicalKeyboardKey.keyR, meta: true),
    label: 'Reload machines and agents',
    group: ShortcutGroup.actions,
  ),
  AppShortcut(
    action: ShortcutAction.showShortcuts,
    activator: SingleActivator(LogicalKeyboardKey.slash, meta: true),
    label: 'Show keyboard shortcuts',
    group: ShortcutGroup.actions,
  ),
];

/// `⌘1`…`⌘9` jump to the nth agent in the sidebar.
///
/// Not in [kAppShortcuts] because nine near-identical rows would bury the sheet;
/// the sheet prints them as one line instead.
const int kAgentDigitCount = 9;

List<SingleActivator> agentDigitActivators() => const [
  SingleActivator(LogicalKeyboardKey.digit1, meta: true),
  SingleActivator(LogicalKeyboardKey.digit2, meta: true),
  SingleActivator(LogicalKeyboardKey.digit3, meta: true),
  SingleActivator(LogicalKeyboardKey.digit4, meta: true),
  SingleActivator(LogicalKeyboardKey.digit5, meta: true),
  SingleActivator(LogicalKeyboardKey.digit6, meta: true),
  SingleActivator(LogicalKeyboardKey.digit7, meta: true),
  SingleActivator(LogicalKeyboardKey.digit8, meta: true),
  SingleActivator(LogicalKeyboardKey.digit9, meta: true),
];

/// Turns the declared shortcuts into the map [CallbackShortcuts] wants.
///
/// A missing handler is left unbound rather than bound to nothing: a key that
/// silently does nothing is worse than a key that was never taken, because the
/// terminal underneath could have had it.
Map<ShortcutActivator, VoidCallback> buildShortcutBindings({
  required Map<ShortcutAction, VoidCallback> handlers,
  void Function(int index)? onSelectAgentIndex,
}) {
  final bindings = <ShortcutActivator, VoidCallback>{};
  for (final shortcut in kAppShortcuts) {
    final handler = handlers[shortcut.action];
    if (handler != null) bindings[shortcut.activator] = handler;
  }
  if (onSelectAgentIndex != null) {
    final digits = agentDigitActivators();
    for (var i = 0; i < digits.length; i++) {
      bindings[digits[i]] = () => onSelectAgentIndex(i);
    }
  }
  return bindings;
}

/// "⌘⇧]" — the way a Mac menu prints it, in the order Apple prints it.
String describeShortcut(SingleActivator activator) {
  final buffer = StringBuffer();
  if (activator.control) buffer.write('⌃');
  if (activator.alt) buffer.write('⌥');
  if (activator.shift) buffer.write('⇧');
  if (activator.meta) buffer.write('⌘');
  buffer.write(_keyLabel(activator.trigger));
  return buffer.toString();
}

String _keyLabel(LogicalKeyboardKey key) {
  // keyLabel spells these out ("Arrow Left"), which is not how a Mac prints a
  // shortcut.
  if (key == LogicalKeyboardKey.arrowLeft) return '←';
  if (key == LogicalKeyboardKey.arrowRight) return '→';
  if (key == LogicalKeyboardKey.arrowUp) return '↑';
  if (key == LogicalKeyboardKey.arrowDown) return '↓';
  if (key == LogicalKeyboardKey.enter) return '⏎';
  if (key == LogicalKeyboardKey.escape) return 'esc';
  return key.keyLabel;
}

/// The chord for [action], ready to append to a tooltip.
///
/// Tooltips read this instead of spelling the keys out, so a rebinding cannot
/// leave a button advertising a key that no longer works.
String? shortcutHintFor(ShortcutAction action) {
  for (final shortcut in kAppShortcuts) {
    if (shortcut.action == action) return describeShortcut(shortcut.activator);
  }
  return null;
}

/// "Reload machines  ⌘R"
String withShortcutHint(String tooltip, ShortcutAction action) {
  final hint = shortcutHintFor(action);
  return hint == null ? tooltip : '$tooltip  $hint';
}
