import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../state/app_state.dart';
import '../state/pending_question.dart';

/// ⌘I — every agent that has stopped to ask you something, across every machine.
///
/// This is not a list that tells you where to go: it is where the answering
/// happens. The daemon hands the question over already shaped — the prompt and
/// its option labels — and the frame that answers it (`question_response`) is
/// the same one the dial sends, so a row can carry the buttons. Four blocked
/// agents can be cleared in four keystrokes without a single pane changing.
///
/// Ordered by who has been waiting longest, because that is the order to work
/// through, not merely a way of sorting.
Future<void> showAttentionInbox(BuildContext context, AppNotifier notifier) {
  return showDialog<void>(
    context: context,
    // Barrier, but a faint one: this sits over a grid of live terminals and
    // blacking them out would hide the very work it is describing.
    barrierColor: Colors.black.withValues(alpha: 0.28),
    builder: (context) => _AttentionInbox(notifier: notifier),
  );
}

class _AttentionInbox extends StatefulWidget {
  const _AttentionInbox({required this.notifier});

  final AppNotifier notifier;

  @override
  State<_AttentionInbox> createState() => _AttentionInboxState();
}

class _AttentionInboxState extends State<_AttentionInbox> {
  /// Selection is by requestId, not by index: the list re-sorts itself as
  /// questions are answered and new ones arrive, and an index would quietly
  /// point at a different agent than the one under the highlight.
  String? _selectedId;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // The ages are the point of the list — a row that says "blocked 4m" and
    // means it is what makes the order meaningful.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  List<PendingQuestion> get _questions => widget.notifier.pendingQuestions;

  PendingQuestion? get _selected {
    final questions = _questions;
    if (questions.isEmpty) return null;
    for (final question in questions) {
      if (question.requestId == _selectedId) return question;
    }
    return questions.first;
  }

  void _move(int delta) {
    final questions = _questions;
    if (questions.isEmpty) return;
    final current = questions.indexOf(_selected!);
    final next = (current + delta).clamp(0, questions.length - 1);
    setState(() => _selectedId = questions[next].requestId);
  }

  void _answer(PendingQuestion question, String option) {
    unawaited(widget.notifier.answerQuestion(question, option));
    // The row is NOT removed here. It leaves when the daemon says the dialog
    // actually left the pane — an answer that could not be keyed in leaves the
    // question standing, which is the truth and is recoverable.
    setState(() {});
  }

  void _open(PendingQuestion question) {
    Navigator.of(context).pop();
    widget.notifier.selectAgent(question.machineId, question.agentId);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _move(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1);
      return KeyEventResult.handled;
    }
    final question = _selected;
    if (question == null) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _open(question);
      return KeyEventResult.handled;
    }
    // 1–9 answers the SELECTED row. Only the selected row prints its numbers,
    // so there is never a question about which agent a digit belongs to.
    final digit = _digit(key);
    if (digit != null &&
        question.answerable &&
        !widget.notifier.isAnswering(question) &&
        digit <= question.options.length) {
      _answer(question, question.options[digit - 1]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  static int? _digit(LogicalKeyboardKey key) {
    const digits = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    final index = digits.indexOf(key);
    return index < 0 ? null : index + 1;
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return AnimatedBuilder(
      animation: widget.notifier,
      builder: (context, _) {
        final questions = _questions;
        final selected = _selected;
        return Dialog(
          // Top-right, where a notification list belongs on this OS — and out
          // of the way of the rail, which is the other thing being read.
          alignment: Alignment.topRight,
          insetPadding: const EdgeInsets.only(top: 44, right: 18),
          backgroundColor: grid.AppGlass.surfaceFill,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
            side: BorderSide(color: grid.AppGlass.hair),
          ),
          child: Focus(
            autofocus: true,
            onKeyEvent: _onKey,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 452, maxHeight: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                // stretch, not start: a row's own header lays out with a
                // Spacer in it, and `start` leaves every child with unbounded
                // width for that flex to fail against.
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(count: questions.length),
                  if (questions.isEmpty)
                    const _Empty()
                  else
                    Flexible(
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: questions.length,
                        itemBuilder: (context, index) {
                          final question = questions[index];
                          return _QuestionRow(
                            key: ValueKey(question.requestId),
                            question: question,
                            agentName: _agentName(question),
                            machineName: _machineName(question),
                            selected: question.requestId == selected?.requestId,
                            answering: widget.notifier.isAnswering(question),
                            onSelect: () => setState(
                              () => _selectedId = question.requestId,
                            ),
                            onAnswer: (option) => _answer(question, option),
                            onOpen: () => _open(question),
                          );
                        },
                      ),
                    ),
                  if (questions.isNotEmpty) const _Footer(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _agentName(PendingQuestion question) {
    final machine = widget.notifier.machineStates[question.machineId];
    for (final agent in machine?.agents ?? const []) {
      if (agent.id == question.agentId) return agent.name;
    }
    // An agent the snapshot has not caught up with is still worth listing: it
    // is blocked either way, and its id is enough to reach it.
    return question.agentId;
  }

  String _machineName(PendingQuestion question) {
    final machine = widget.notifier.machineStates[question.machineId];
    final engine = _engineFor(machine, question.agentId);
    final name = machine?.machine.displayName ?? question.machineId;
    return engine == null ? name : '$name · $engine';
  }

  String? _engineFor(MachineState? machine, String agentId) {
    for (final agent in machine?.agents ?? const []) {
      if (agent.id == agentId) return agent.engineDisplayName ?? agent.engine;
    }
    return null;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: grid.AppPalette.divider)),
      ),
      child: Row(
        children: [
          Text(
            count == 0 ? 'Waiting on you' : 'Waiting on you · $count',
            style: TextStyle(
              color: grid.AppPalette.textSecondary,
              fontSize: 11.5,
              letterSpacing: 0.9,
              fontWeight: grid.AppFont.medium,
            ),
          ),
          const Spacer(),
          Text(
            '⌘I',
            style: TextStyle(
              color: grid.AppPalette.textFaint,
              fontSize: 11.5,
              fontFamily: grid.AppFont.mono,
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 24),
      child: Text(
        'Nothing is waiting on you.',
        style: TextStyle(
          color: grid.AppPalette.textFaint,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 9, 16, 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: grid.AppPalette.divider)),
      ),
      child: Text(
        '1–9 answers the selected agent · ↵ opens its pane · ↑↓ moves',
        style: TextStyle(color: grid.AppPalette.textFaint, fontSize: 11),
      ),
    );
  }
}

class _QuestionRow extends StatelessWidget {
  const _QuestionRow({
    super.key,
    required this.question,
    required this.agentName,
    required this.machineName,
    required this.selected,
    required this.answering,
    required this.onSelect,
    required this.onAnswer,
    required this.onOpen,
  });

  final PendingQuestion question;
  final String agentName;
  final String machineName;
  final bool selected;
  final bool answering;
  final VoidCallback onSelect;
  final ValueChanged<String> onAnswer;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSelect,
      onDoubleTap: onOpen,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? grid.AppSurface.selectedFill : Colors.transparent,
          // The amber stripe is the row's own left border rather than a child:
          // a child would have to stretch to the row's height, and a Row inside
          // a list has no height to stretch to. Amber, and never the accent —
          // the focused pane already wears an accent border, so blue here would
          // be a second thing meaning something else.
          border: Border(
            left: BorderSide(color: grid.AppPalette.warn, width: 3),
          ),
        ),
        // 13, not 16: the border sits inside the box, so this keeps the text on
        // the same line it would be on without it.
        padding: const EdgeInsets.fromLTRB(13, 12, 16, 13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          agentName,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: grid.AppPalette.textPrimary,
                            fontSize: 13.5,
                            fontWeight: grid.AppFont.medium,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          machineName,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: grid.AppPalette.textFaint,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        answering ? 'answering…' : _age(question.since),
                        style: TextStyle(
                          color: answering
                              ? grid.AppPalette.textFaint
                              : grid.AppPalette.warn,
                          fontSize: 11,
                          fontFamily: grid.AppFont.mono,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    question.prompt,
                    style: TextStyle(
                      color: grid.AppPalette.textSecondary,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                  if (question.answerable) ...[
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (var i = 0; i < question.options.length; i++)
                          _OptionChip(
                            label: question.options[i],
                            // Numbers only on the selected row: they act on the
                            // selection, so printing them everywhere would
                            // promise nine agents can be answered by one digit.
                            number: selected ? i + 1 : null,
                            enabled: !answering,
                            onTap: () => onAnswer(question.options[i]),
                          ),
                      ],
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    // A multi-select needs more than one option keyed in and
                    // this reply carries one string, so it says so instead of
                    // offering half an answer.
                    Text(
                      'Pick several — open the pane to answer.',
                      style: TextStyle(
                        color: grid.AppPalette.textFaint,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _age(DateTime since) {
    final seconds = DateTime.now().difference(since).inSeconds;
    if (seconds < 60) return 'blocked ${seconds}s';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return 'blocked ${minutes}m';
    return 'blocked ${minutes ~/ 60}h${minutes % 60}m';
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.number,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final int? number;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final highlight = number != null && enabled;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: EdgeInsets.fromLTRB(number == null ? 9 : 5, 4, 9, 4),
          decoration: BoxDecoration(
            color: highlight
                ? grid.AppSurface.accentWash
                : grid.AppSurface.hoverFill,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: grid.AppGlass.hair),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (number != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: grid.AppPalette.warn,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$number',
                    style: TextStyle(
                      color: grid.AppPalette.windowBg,
                      fontSize: 10.5,
                      fontFamily: grid.AppFont.mono,
                      fontWeight: grid.AppFont.medium,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: grid.AppPalette.textPrimary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
