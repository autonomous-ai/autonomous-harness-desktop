import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../theme/app_theme.dart';
import '../terminal/terminal_font_store.dart';
import '../terminal/terminal_session.dart';

/// A textbox under a terminal that sends its whole contents at once.
///
/// It exists for remote machines, where typing straight into the pane charges a network round trip
/// per keystroke. Here the typing is local and free; only the finished message crosses the wire —
/// as one batch, followed by Enter.
///
/// Focusing the terminal itself is untouched: that path stays per-keystroke, which is what anyone
/// driving a full-screen TUI needs.
class TerminalComposer extends StatefulWidget {
  const TerminalComposer({
    super.key,
    required this.session,
    required this.focusNode,
  });

  final TerminalSession session;
  final FocusNode focusNode;

  @override
  State<TerminalComposer> createState() => _TerminalComposerState();
}

class _TerminalComposerState extends State<TerminalComposer> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSessionChanged);
    terminalFontStore.addListener(_onFontChanged);
  }

  @override
  void didUpdateWidget(TerminalComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      oldWidget.session.removeListener(_onSessionChanged);
      widget.session.addListener(_onSessionChanged);
      // The tile was pointed at another agent. Whatever was half-typed was meant for the previous
      // one, and silently sending it to its replacement would be worse than losing it.
      _controller.clear();
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    terminalFontStore.removeListener(_onFontChanged);
    _controller.dispose();
    super.dispose();
  }

  /// Enabled-ness follows the stream's status, so a rebuild is needed when it moves.
  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  /// Keeps this box's face in step with the terminal above it — see the `style:` comment below.
  void _onFontChanged() {
    if (mounted) setState(() {});
  }

  /// Guards the settle window inside [TerminalSession.sendComposerText]: the body is already in
  /// the pane while we wait to submit it, so a second Enter arriving in that window would type
  /// the next message into the middle of the one being sent.
  bool _sending = false;

  Future<void> _submit() async {
    if (_sending) return;
    final text = _controller.text;
    if (text.isEmpty) return;
    _sending = true;
    try {
      if (!await widget.session.sendComposerText(text)) return;
      _controller.clear();
    } finally {
      _sending = false;
    }
  }

  /// Enter sends; Shift+Enter is left to the field so it inserts a newline.
  ///
  /// `TextField.onSubmitted` cannot do this — it never fires for a multi-line field.
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final isEnter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isShiftPressed) return KeyEventResult.ignored;
    unawaited(_submit());
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.session.acceptsInput;
    // No top border of its own: [ComposerGrip] is the line between this and the terminal.
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
      // ⚠️ The composer belongs to the TERMINAL, not to the app's chrome, so it
      // is held out of the app-wide UI text scale twice over — once for its
      // type here, and once for its BOX below. Both are needed, and for
      // different reasons.
      //
      // This half keeps the typed text at the terminal's own size. What is
      // typed here lands over there, so it has to look like it.
      child: MediaQuery.withNoTextScaling(
        child: Focus(
          onKeyEvent: _onKeyEvent,
          child: TextField(
            controller: _controller,
            focusNode: widget.focusNode,
            enabled: enabled,
            minLines: 1,
            maxLines: 6,
            // The message is going to a terminal, so it is shown in the terminal's own face: what
            // is typed here should look like what will land over there.
            style: TextStyle(
              color: grid.AppPalette.textPrimary,
              fontFamily: terminalFontStore.value.fontFamily,
              fontFamilyFallback: terminalFontStore.value.fontFamilyFallback,
              fontSize: terminalFontStore.value.fontSize,
            ),
            textInputAction: TextInputAction.newline,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              // ⚠️ THE BOX, pinned explicitly — and `withNoTextScaling` above
              // does NOT cover this.
              //
              // `inputDecorationTheme` sizes every field from
              // `AppControl.heightFieldScaled` and a padding multiplied by
              // `AppFont.uiScale` — a plain static, not a MediaQuery, so no
              // scaling scope can hold it back. Left inherited, raising the UI
              // size grows this box (36 → 48.9 at the top of the range), which
              // shrinks the Expanded holding the terminal, which drops a row,
              // which sends a `terminal_resize` to the remote agent. The
              // composer only appears for REMOTE machines, so that is the only
              // case where it would ever have bitten.
              //
              // These two lines are the app's own resting values, stated rather
              // than derived, so the pane's row count cannot move with a
              // setting that has nothing to do with the terminal.
              isDense: true,
              constraints: const BoxConstraints(minHeight: 36),
              // 9.225 is not a taste — it is `(36 - 13 * 1.35) / 2`, exactly
              // what `inputDecorationTheme` derives at `uiScale == 1`
              // (app_theme.dart:1100-1106). Stated rather than inherited, so
              // this box renders identically to today and cannot drift with a
              // setting that has nothing to do with the terminal.
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 9.225,
              ),
              hintText: enabled
                  // Says what the box is FOR, not just how it works: that it is the fast path,
                  // and that the terminal above is still there for selecting and copying. ⇧⏎ is
                  // left unadvertised on purpose — it is the one a user stumbles into anyway, and
                  // the room buys the selection hint, which nobody guesses.
                  ? 'Fast input · ⏎ send · select in the terminal above'
                  : 'Terminal is not accepting input',
            ),
          ),
        ),
      ),
    );
  }
}

/// The handle that opens and closes the composer, sitting on the line between the terminal and the
/// box it controls.
///
/// It deliberately lives OUTSIDE [TerminalComposer]: a control kept inside would vanish along with
/// the thing it hides, leaving no way back. On the divider it also keeps ONE fixed position in both
/// states — the target never moves, so closing and reopening is the same click twice.
class ComposerGrip extends StatelessWidget {
  const ComposerGrip({
    super.key,
    required this.expanded,
    required this.onPressed,
  });

  final bool expanded;
  final VoidCallback onPressed;

  /// Tall enough to take a click, short enough that a collapsed pane gives the terminal back
  /// essentially every row the box was using.
  static const double height = 16;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return SizedBox(
      height: height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(height: 1, color: AppColors.border),
          Tooltip(
            message: expanded ? 'Hide the send box' : 'Show the send box',
            child: Material(
              color: grid.AppPalette.windowBg,
              // `borderStrong`, not `border`: the faint one is a SEPARATOR token, sized to be
              // findable at a seam the eye is already on. This rim has to hold a shape against
              // terminal output, which is what the stronger hairline exists for.
              shape: StadiumBorder(
                side: BorderSide(color: AppColors.borderStrong),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onPressed,
                child: SizedBox(
                  width: 40,
                  height: height,
                  child: Icon(
                    expanded
                        ? LucideIcons.chevronDown300
                        : LucideIcons.chevronUp300,
                    size: 12,
                    // One step up from the faint ink this started on, in both directions at once:
                    // the token resolves lighter on dark and darker on light, so the glyph gains
                    // contrast against the pane either way instead of only one of them.
                    color: AppColors.mutedStrong,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
