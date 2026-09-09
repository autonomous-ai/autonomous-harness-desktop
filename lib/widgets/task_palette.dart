import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../shared/theme/app_theme.dart' as grid;
import '../state/app_state.dart';

/// ⌘K — describe the work, and let the daemon say whose it is.
///
/// A TASK BOX, not a command palette. There is no list of actions to fuzzy-match and no agent search:
/// the whole interface is one field, and the answer to "which agent" is the router's job, not the
/// typist's. That is the point of the feature — the moment it also does lookup, the field has to guess
/// whether a word is a task or a name, and it will guess wrong on the short ones.
///
/// It is the same router the dial has always used (`routeVoiceTask`), which has never cared that its
/// input arrived as speech. What is new is that the answer comes back to a surface that can SHOW it: the
/// dial had to act on a pick it could not explain, a window can hold it up and ask.
///
/// CONFIDENT WORK IS SILENT, UNSURE WORK ASKS. Above the threshold the palette closes and the pane
/// simply becomes that agent — the text arriving in the terminal is the receipt, and a toast on top of it
/// would be a second one. Below it, nothing is sent and the runners-up are offered instead.
Future<void> showTaskPalette(BuildContext context, AppNotifier notifier) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    builder: (context) => _TaskPalette(notifier: notifier),
  );
}

/// Below this the palette stops guessing and asks.
///
/// It is not a tuned number, it is the router's own vocabulary: the classifier is told to answer ~0.3
/// when nothing fits and 0.85+ when something clearly does, and the heuristic fallback — the name
/// matcher used when the model times out or cannot run — is CAPPED at 0.4. So a router that failed
/// always lands under this line, which means "the router broke" and "the router is unsure" arrive at the
/// same place: a question, never a silent wrong guess.
const double _confidentEnough = 0.5;

class _TaskPalette extends StatefulWidget {
  const _TaskPalette({required this.notifier});

  final AppNotifier notifier;

  @override
  State<_TaskPalette> createState() => _TaskPaletteState();
}

enum _Stage { typing, routing, choosing, empty }

class _TaskPaletteState extends State<_TaskPalette> {
  final TextEditingController _text = TextEditingController();

  /// THE KEYS ARE HANDLED ON THIS NODE, not on a Focus above the field, and not through onSubmitted.
  ///
  /// A multi-line TextField consumes Enter itself — it inserts a newline and never calls onSubmitted —
  /// and key events travel from the focused node UPWARDS, so an ancestor Focus is asked only about the
  /// keys the field did not want. Enter was never one of them. A FocusNode's own onKeyEvent runs while
  /// the event is dispatched TO the node, ahead of the editing shortcuts that would type the newline, so
  /// this is the one place that can take Enter back.
  late final FocusNode _field = FocusNode(onKeyEvent: _onFieldKey);

  _Stage _stage = _Stage.typing;
  String _note = '';

  /// Which half of the wait is on screen — choosing an agent, or handing the task over.
  bool _sending = false;
  List<RouteCandidate> _choices = const [];
  int _cursor = 0;

  /// Which question is still ours. A second Enter — or an Esc and a re-open — must not let a slow first
  /// answer arrive and act: it belongs to a palette state nobody is looking at any more.
  int _generation = 0;

  @override
  void dispose() {
    _generation++; // anything still in flight now answers to nobody
    _text.dispose();
    _field.dispose();
    super.dispose();
  }

  Future<void> _route() async {
    final task = _text.text.trim();
    if (task.isEmpty || _stage == _Stage.routing) return;
    final mine = ++_generation;
    setState(() {
      _stage = _Stage.routing;
      _sending = false;
      _note = '';
    });

    final answer = await widget.notifier.routeTask(task);
    if (!mounted || mine != _generation) return;

    // Nobody to ask, or nobody to pick from. Say which — "no agents here" and "the daemon is not up" are
    // different problems and lead to different next moves.
    if (answer == null) {
      setState(() {
        _stage = _Stage.empty;
        _note = widget.notifier.localMachineState == null
            ? 'No local machine is connected yet.'
            : 'Could not reach the router on this computer.';
      });
      return;
    }
    if (answer.isEmpty) {
      setState(() {
        _stage = _Stage.empty;
        _note = 'There is no agent on this computer to send that to.';
      });
      return;
    }

    if (answer.confidence >= _confidentEnough) {
      await _commit(answer.agentId, answer.machineId, task);
      return;
    }
    setState(() {
      _stage = _Stage.choosing;
      _choices = answer.candidates;
      _cursor = 0;
    });
  }

  Future<void> _commit(String agentId, String machineId, String task) async {
    // NOT closed before the send any more.
    //
    // It used to close first, so a fast route never showed a modal over the pane it was about to fill.
    // But the delivery can fail — a machine that stopped answering takes the turn and nothing comes back
    // — and closing first meant that failure had nowhere to appear: the palette was gone, the pane never
    // changed, and the person was left with a task that had simply evaporated. Measured on the desk with
    // a remote machine whose link was timing out.
    //
    // So it waits for the answer. A successful send is still quiet — the window closes and the pane
    // becomes the agent's — it just closes a moment later than it did.
    setState(() {
      _stage = _Stage.routing;
      _sending = true;
      _note = '';
    });
    final failure = await widget.notifier.sendRoutedTask(
      agentId,
      machineId,
      task,
    );
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _stage = _Stage.empty;
      _note = failure;
    });
  }

  KeyEventResult _onFieldKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    final isEnter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    // ⇧Enter is the newline — ignored here so the field does what it always does with it.
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (isEnter && !shift && _stage != _Stage.choosing) {
      unawaited(_route());
      return KeyEventResult.handled; // …and NOT a newline
    }
    if (_stage != _Stage.choosing) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _cursor = (_cursor + 1).clamp(0, _choices.length - 1));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => _cursor = (_cursor - 1).clamp(0, _choices.length - 1));
      return KeyEventResult.handled;
    }
    if (isEnter && !shift) {
      final pick = _choices[_cursor.clamp(0, _choices.length - 1)];
      unawaited(_commit(pick.agentId, pick.machineId, _text.text.trim()));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Dialog(
      // Centred. It was pinned near the top out of palette habit, but this one is not a list you scan
      // while reading the screen behind it — it is a single field that owns the moment, and the eye is
      // already in the middle of the window.
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      backgroundColor: grid.AppGlass.surfaceFill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(color: grid.AppGlass.hair),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
              child: TextField(
                controller: _text,
                focusNode: _field,
                autofocus: true,
                maxLines: 4,
                minLines: 1,
                // Enter routes; a newline needs the modifier. The field is for a sentence, not a
                // document, and the common case must not cost a reach for the mouse.
                // Read-only rather than disabled while the router thinks: a disabled field drops the
                // focus, and the focus is what Esc is listening on.
                readOnly: _stage == _Stage.routing,
                style: TextStyle(
                  color: grid.AppPalette.textPrimary,
                  fontSize: 15,
                  height: 1.4,
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  hintText: 'Describe the work…',
                  hintStyle: TextStyle(
                    color: grid.AppPalette.textFaint,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            _footer(context),
          ],
        ),
      ),
    );
  }

  Widget _footer(BuildContext context) {
    switch (_stage) {
      case _Stage.typing:
        return _hint('Enter to send · ⇧Enter for a new line · Esc to close');
      case _Stage.routing:
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
          child: Row(
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: grid.AppPalette.textFaint,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _sending ? 'sending…' : 'choosing an agent…',
                style: TextStyle(
                  color: grid.AppPalette.textSecondary,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        );
      case _Stage.empty:
        return _hint(_note);
      case _Stage.choosing:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 8),
              child: Text(
                // Said plainly. The number behind this is the router's confidence, and dressing the
                // moment up as a choice the person wanted to make would hide that it is a fallback.
                'Not sure which agent — pick one:',
                style: TextStyle(
                  color: grid.AppPalette.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            for (var i = 0; i < _choices.length; i++)
              _row(_choices[i], i == _cursor),
            _hint('↑↓ to choose · Enter to send · Esc to close'),
          ],
        );
    }
  }

  Widget _row(RouteCandidate candidate, bool active) {
    return InkWell(
      onTap: () => unawaited(
        _commit(candidate.agentId, candidate.machineId, _text.text.trim()),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 9, 18, 9),
        color: active ? grid.AppGlass.surfaceHoverFill : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    candidate.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: grid.AppPalette.textPrimary,
                      fontSize: 13.5,
                      fontWeight: active
                          ? grid.AppFont.medium
                          : grid.AppFont.regular,
                    ),
                  ),
                ),
                // Which computer, beside the name. The list spans every machine now, so two agents
                // called the same thing on two of them are one row twice without it.
                if (candidate.machine.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    candidate.machine,
                    style: TextStyle(
                      color: grid.AppPalette.textFaint,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
            if (candidate.recent.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                candidate.recent,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: grid.AppPalette.textFaint,
                  fontSize: 11.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _hint(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
    child: Text(
      text,
      style: TextStyle(color: grid.AppPalette.textFaint, fontSize: 11.5),
    ),
  );
}
