import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../shared/theme/app_theme.dart' as grid;
import '../state/app_state.dart';
import 'engine_identity.dart';

/// ⌘B — describe the work, and let the daemon say whose it is.
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
/// It is not a tuned number, it is the router's own top band: the classifier is told to answer **0.85+
/// when the name and/or recent activity CLEARLY match**, ~0.6 for "reasonable but not certain", and ~0.3
/// when nothing fits and it is naming the closest agent anyway. Sitting the line exactly on 0.85 means
/// this window sends in silence only when the router used the word "clearly" — every softer answer,
/// including the ones it called reasonable, becomes a question.
///
/// It was 0.5, and 0.5 was measured to be inside the model's own noise. The same task — "so sanh iphone
/// vs samsung" — routed twice seven minutes apart came back 0.35 and 0.80: once a question, once a silent
/// send, to two DIFFERENT agents. A threshold a small classifier can cross by chance is not a threshold,
/// and the wrong side of it is a task delivered to the wrong agent with nothing on screen to say so.
///
/// The cost is deliberate and worth naming: more asking. A "reasonable" 0.6 pick now stops for a keypress
/// it used to skip. That trade is the right way round — a question costs one Enter, a silent wrong route
/// costs a turn on the wrong agent and the time to notice.
///
/// The heuristic fallback is unaffected and stays what it was: capped at 0.4, so a router that could not
/// run has never been able to reach this line and still cannot. "The router broke" and "the router is
/// unsure" arrive at the same place — a question, never a silent wrong guess.
const double _confidentEnough = 0.85;

class _TaskPalette extends StatefulWidget {
  const _TaskPalette({required this.notifier});

  final AppNotifier notifier;

  @override
  State<_TaskPalette> createState() => _TaskPaletteState();
}

/// [sent] is a BEAT, not a screen. See [_confirmBeat].
enum _Stage { typing, routing, choosing, empty, sent }

/// How long the receipt stays up before the palette closes itself.
///
/// A confident route used to close the instant the daemon answered, on the rule that the text landing in
/// the terminal is the receipt. It is — but only if you are looking at that pane, and ⌘B is most useful
/// exactly when you are not: the agent it picks is often on another machine and behind another tile. So
/// the window says who took the work, briefly, and then gets out of the way. Long enough to read four
/// words, short enough that nobody waits on it.
const Duration _confirmBeat = Duration(milliseconds: 750);

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

  /// The answer itself, kept because the picker explains ITSELF with it: how many agents were weighed,
  /// across how many computers, and whether a classifier or the name matcher produced this.
  RouteAnswer? _answer;

  /// Who took the work — held for the receipt beat only.
  String _sentName = '';
  String _sentMachine = '';

  /// Seconds on the clock while the router thinks.
  ///
  /// The wait can run to twenty seconds, and a spinner that says nothing for that long reads as a hang.
  /// A number that moves is the difference between "it is working" and "it has stopped".
  Timer? _ticker;
  int _elapsed = 0;

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
    _ticker?.cancel();
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
      _answer = null;
    });
    _startClock();

    final answer = await widget.notifier.routeTask(task);
    if (!mounted || mine != _generation) return;
    _stopClock();

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
      _answer = answer; // so the receipt can name who took it
      await _commit(answer.agentId, answer.machineId, task);
      return;
    }
    setState(() {
      _stage = _Stage.choosing;
      _answer = answer;
      _choices = answer.candidates;
      _cursor = 0;
    });
  }

  /// One second at a time, and only while something is actually in flight.
  void _startClock() {
    _ticker?.cancel();
    _elapsed = 0;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed++);
    });
  }

  void _stopClock() {
    _ticker?.cancel();
    _ticker = null;
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
    final mine = ++_generation;
    setState(() {
      _stage = _Stage.routing;
      _sending = true;
      _note = '';
    });
    _startClock();
    final failure = await widget.notifier.sendRoutedTask(
      agentId,
      machineId,
      task,
    );
    if (!mounted || mine != _generation) return;
    _stopClock();
    if (failure != null) {
      setState(() {
        _stage = _Stage.empty;
        _note = failure;
      });
      return;
    }
    // Landed. Name who took it, then close — see [_confirmBeat].
    final taker = _named(agentId);
    setState(() {
      _stage = _Stage.sent;
      _sentName = taker?.name ?? _answer?.name ?? '';
      _sentMachine = taker?.machine ?? '';
    });
    await Future<void>.delayed(_confirmBeat);
    if (!mounted || mine != _generation) return;
    Navigator.of(context).pop();
  }

  /// The candidate row for an id, when the answer carried one. The winner is always among them, so a
  /// confident route can name its taker without a second lookup.
  RouteCandidate? _named(String agentId) {
    for (final candidate in _answer?.candidates ?? const <RouteCandidate>[]) {
      if (candidate.agentId == agentId) return candidate;
    }
    return null;
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
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: grid.AppGlass.hair),
      ),
      // NARROWER than it was, and shorter: at rest this is one line of text in a box, and every pixel it
      // takes is a pixel of the terminal it is covering.
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                _stage == _Stage.typing ? 20 : 14,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _input()),
                  // The only furniture at rest. It says what to press without spending a row on saying it.
                  if (_stage == _Stage.typing) ...[
                    const SizedBox(width: 12),
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: _Chord('⏎'),
                    ),
                  ],
                ],
              ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  /// The field, with Material's own skin switched OFF.
  ///
  /// ⚠️ `filled: false`, `isCollapsed: true` and the four explicit `InputBorder.none`s are load-bearing,
  /// not tidying — the same trap `ShareTextField` documents. The app's global [InputDecorationTheme] sets
  /// `filled: true`, a `minHeight` sized for a 32px control, and a focus ring on all three border slots.
  /// `border: InputBorder.none` alone does NOT win: `enabledBorder` and `focusedBorder` are consulted
  /// first, so the field drew a rounded pill in the app's grey INSIDE this dialog's own box — two nested
  /// boxes around one line of text, which is exactly what made the first cut of this palette look cheap.
  Widget _input() {
    return TextField(
      controller: _text,
      focusNode: _field,
      autofocus: true,
      maxLines: 4,
      minLines: 1,
      // Enter routes; a newline needs the modifier. The field is for a sentence, not a document, and the
      // common case must not cost a reach for the mouse.
      // Read-only rather than disabled while the router thinks: a disabled field drops the focus, and the
      // focus is what Esc is listening on.
      readOnly: _stage == _Stage.routing || _stage == _Stage.sent,
      // Big, because the field IS the interface here. There is nothing else to look at, and a sentence
      // you are about to send to a machine deserves to be read back before you press Enter.
      style: TextStyle(
        color: grid.AppPalette.textPrimary,
        fontSize: 20,
        height: 1.35,
      ),
      cursorColor: grid.AppPalette.accentOnSurface,
      cursorWidth: 1.5,
      decoration: InputDecoration(
        filled: false,
        isDense: true,
        isCollapsed: true,
        contentPadding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        hintText: 'Describe the work…',
        hintStyle: TextStyle(
          color: grid.AppPalette.textFaint,
          fontSize: 20,
          height: 1.35,
        ),
      ),
    );
  }

  Widget _footer() {
    switch (_stage) {
      // Nothing at all. The keycap beside the field has already said the one thing that matters, and a
      // box with nothing in it is the point: at rest this palette is 60px of window instead of 130.
      case _Stage.typing:
        return const SizedBox.shrink();

      case _Stage.routing:
      case _Stage.sent:
        return _working();

      case _Stage.empty:
        return _lines([
          _muted(_note),
          const SizedBox(height: 10),
          const _Keys([('⏎', 'try again'), ('esc', 'close')]),
        ]);

      case _Stage.choosing:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: _askedWhy(),
            ),
            for (var i = 0; i < _choices.length; i++)
              _row(_choices[i], i == _cursor),
            _lines([
              const SizedBox(height: 4),
              const _Keys([('↑↓', 'choose'), ('⏎', 'send'), ('esc', 'close')]),
            ]),
          ],
        );
    }
  }

  /// One column of text, in the field's own left margin. Everything this palette says lines up under the
  /// sentence it is about.
  Widget _lines(List<Widget> children) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );

  Widget _muted(String text) => Text(
    text,
    style: TextStyle(
      color: grid.AppPalette.textSecondary,
      fontSize: 12.5,
      height: 1.45,
    ),
  );

  /// Why it is asking, and what it looked at before it gave up — one line, no heading.
  ///
  /// Two different sentences, and the difference is the point: a classifier that WAS unsure and a router
  /// that could not run at all both land here — deliberately, so a broken router can never guess — but
  /// they send a person to different next moves. One means "say it differently"; the other means
  /// something on this computer is not working.
  Widget _askedWhy() {
    final answer = _answer;
    final heuristic = answer?.via == 'heuristic';
    final reason = (answer?.reason ?? '').trim();
    final weighed = answer?.weighed ?? 0;
    final machines = answer?.machines ?? 0;
    final looked = weighed == 0
        ? ''
        : machines > 1
        ? 'Weighed $weighed agents on $machines computers — '
        : 'Weighed $weighed agents — ';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          heuristic
              ? '${looked}the router could not run, so these are name matches'
              : '${looked}not sure enough to send it',
          style: TextStyle(
            color: grid.AppPalette.textSecondary,
            fontSize: 12.5,
          ),
        ),
        // The router's own words. It has always sent them and the window has always dropped them, which
        // left the person guessing at a judgement the machine had already explained.
        if (!heuristic && reason.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            '“$reason”',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: grid.AppPalette.textFaint,
              fontSize: 11.5,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }

  /// The wait and the receipt: one line of text, and a hairline at the very bottom edge.
  ///
  /// No spinner and no stepper — this palette has no chrome to put them in. What it does say is WHICH
  /// half of the wait is running (the two take different times and only one can be slow for a reason you
  /// could act on) and, past five seconds, how long. Under five a clock is noise; over it, it is the
  /// difference between working and stopped.
  Widget _working() {
    final done = _stage == _Stage.sent;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Row(
            children: [
              if (done) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: grid.AppPalette.online,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  done
                      ? 'Sent to ${_sentName.isEmpty ? 'the agent' : _sentName}'
                            '${_sentMachine.isEmpty ? '' : ' · $_sentMachine'}'
                      : _sending
                      ? 'handing it over…'
                      : 'choosing an agent…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: done
                        ? grid.AppPalette.textSecondary
                        : grid.AppPalette.textFaint,
                    fontSize: 12.5,
                  ),
                ),
              ),
              if (!done && _elapsed >= 5)
                Text(
                  '${_elapsed}s',
                  style: TextStyle(
                    color: grid.AppPalette.textFaint,
                    fontSize: 11.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
        ),
        // The only moving part in the whole palette, and it sits on the edge rather than in the column —
        // a progress bar in the text would be one more thing to look at while reading.
        SizedBox(
          height: 2,
          child: done
              ? ColoredBox(color: grid.AppPalette.online)
              : LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation(
                    grid.AppPalette.accentOnSurface,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _row(RouteCandidate candidate, bool active) {
    final fit = candidate.confidence;
    return InkWell(
      onTap: () => unawaited(
        _commit(candidate.agentId, candidate.machineId, _text.text.trim()),
      ),
      child: Container(
        color: active ? grid.AppGlass.surfaceHoverFill : null,
        padding: const EdgeInsets.fromLTRB(0, 8, 20, 8),
        child: Row(
          children: [
            // The cursor, as a rail rather than the fill alone: on rows this quiet a tint change is easy
            // to miss, and this is the row Enter acts on.
            Container(
              width: 2,
              height: 32,
              decoration: BoxDecoration(
                color: active ? grid.AppPalette.accent : Colors.transparent,
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(2),
                ),
              ),
            ),
            const SizedBox(width: 18),
            // The SAME mark the rail draws for this agent. A picker that invented its own would make the
            // row and the rail read as two lists that happen to share names.
            EngineMark(engine: candidate.engine, size: 15),
            const SizedBox(width: 10),
            Expanded(
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
                      // Which computer, as a chip rather than grey text trailing the name: the list spans
                      // every machine, so two agents called the same thing on two of them are one row
                      // twice without it — and a chip survives a long name where trailing text does not.
                      if (candidate.machine.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        _MachineChip(candidate.machine),
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
            // The fit, as the number and nothing else. A bar would be chrome, and this palette has none;
            // three numbers in a column already say "near-tie" or "clear leader" at a glance.
            //
            // Drawn only where there IS one: 0 means the router said nothing about this candidate, and a
            // printed 0.00 would be a claim it never made.
            if (fit > 0) ...[
              const SizedBox(width: 12),
              Text(
                fit.toStringAsFixed(2),
                style: TextStyle(
                  color: active
                      ? grid.AppPalette.textSecondary
                      : grid.AppPalette.textFaint,
                  fontSize: 11.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A key, drawn as a key — small enough to read as a hint rather than as a button.
class _Chord extends StatelessWidget {
  const _Chord(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: grid.AppGlass.hair),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: grid.AppPalette.textFaint,
          fontSize: 10.5,
          height: 1.1,
        ),
      ),
    );
  }
}

class _Keys extends StatelessWidget {
  const _Keys(this.pairs);

  final List<(String, String)> pairs;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (chord, what) in pairs)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Chord(chord),
              const SizedBox(width: 6),
              Text(
                what,
                style: TextStyle(
                  color: grid.AppPalette.textFaint,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _MachineChip extends StatelessWidget {
  const _MachineChip(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: grid.AppGlass.hair),
      ),
      child: Text(
        name,
        style: TextStyle(color: grid.AppPalette.textFaint, fontSize: 10.5),
      ),
    );
  }
}
