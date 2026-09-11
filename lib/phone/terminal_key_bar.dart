import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../shared/theme/app_theme.dart';

/// The keys a touch keyboard does not have, over the terminal on a phone.
///
/// Every agent CLI wants Esc, Tab, the arrows and Ctrl-C, and an iOS or Android software keyboard
/// offers none of them. Without this row a phone can type prose at an agent and nothing else — it
/// cannot answer a TUI prompt, cancel a run, or walk shell history.
///
/// The keys go through [Terminal.keyInput], the SAME path a hardware keyboard takes, rather than
/// through a new method on `TerminalSession`: xterm turns the key into the right escape sequence
/// for the mode the pane is in (application vs normal cursor keys), which is exactly the part that
/// would be wrong if this wrote bytes itself.
class TerminalKeyBar extends StatefulWidget {
  const TerminalKeyBar({
    super.key,
    required this.terminal,
    this.enabled = true,
  });

  final Terminal terminal;

  /// False while the session cannot take input — the row stays visible but dimmed, so it does not
  /// appear and disappear under the thumb as a connection wobbles.
  final bool enabled;

  @override
  State<TerminalKeyBar> createState() => _TerminalKeyBarState();
}

class _TerminalKeyBarState extends State<TerminalKeyBar> {
  /// Ctrl LATCHES rather than being held.
  ///
  /// A finger cannot hold one key while pressing another, so the modifier has to survive until the
  /// next press. It clears on that press — one Ctrl, one combination, the way a phone's own shift
  /// key behaves.
  bool _ctrl = false;

  void _send(TerminalKey key) {
    if (!widget.enabled) return;
    widget.terminal.keyInput(key, ctrl: _ctrl);
    if (_ctrl) setState(() => _ctrl = false);
  }

  void _toggleCtrl() {
    if (!widget.enabled) return;
    setState(() => _ctrl = !_ctrl);
  }

  /// Ctrl-C as one press, because interrupting a run is the single most-wanted key here and
  /// latching Ctrl then finding C is three taps for the thing people need in one.
  void _interrupt() {
    if (!widget.enabled) return;
    widget.terminal.keyInput(TerminalKey.keyC, ctrl: true);
    if (_ctrl) setState(() => _ctrl = false);
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Opacity(
      opacity: widget.enabled ? 1 : 0.4,
      child: SizedBox(
        height: kTerminalKeyBarHeight,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            _Key(label: 'esc', onTap: () => _send(TerminalKey.escape)),
            _Key(label: 'ctrl', latched: _ctrl, onTap: _toggleCtrl),
            _Key(label: 'tab', onTap: () => _send(TerminalKey.tab)),
            _Key(label: '↑', onTap: () => _send(TerminalKey.arrowUp)),
            _Key(label: '↓', onTap: () => _send(TerminalKey.arrowDown)),
            _Key(label: '←', onTap: () => _send(TerminalKey.arrowLeft)),
            _Key(label: '→', onTap: () => _send(TerminalKey.arrowRight)),
            _Key(label: '^C', onTap: _interrupt),
            _Key(label: 'home', onTap: () => _send(TerminalKey.home)),
            _Key(label: 'end', onTap: () => _send(TerminalKey.end)),
          ],
        ),
      ),
    );
  }
}

/// The row's height, named so the page reserving room for it and the row itself cannot disagree.
const double kTerminalKeyBarHeight = 44;

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.onTap, this.latched = false});

  final String label;
  final VoidCallback onTap;
  final bool latched;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.only(right: 6, top: 6, bottom: 6),
      child: Material(
        color: latched ? AppSurface.accentWash : AppGlass.surfaceFill,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: Container(
            constraints: const BoxConstraints(minWidth: 42),
            padding: const EdgeInsets.symmetric(horizontal: 11),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: latched ? AppPalette.accentOnSurface : AppGlass.hair,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: AppFont.mono,
                fontFamilyFallback: AppFont.monoFallback,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: latched
                    ? AppPalette.accentOnSurface
                    : AppPalette.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
