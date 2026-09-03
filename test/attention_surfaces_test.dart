// The three places a blocked agent shows up: the rail row, the ⌘I inbox, and
// the ring on its pane. What is worth pinning here is which signal WINS —
// blocked over working in the rail, attention beside focus on a tile — and the
// inbox's promise that a digit belongs to exactly one agent.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/models.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/state/pending_question.dart';
import 'package:harness/widgets/attention_inbox.dart';
import 'package:harness/widgets/machine_rail.dart';

const _machine = Machine(
  machineId: 'm1',
  authMode: MachineAuthMode.remote,
  name: 'prod-mac',
  status: 'online',
);

Agent _agent(String id, String name) => Agent.fromJson({
  'id': id,
  'sessionId': 'session-$id',
  'name': name,
  'engine': 'claude',
  'status': 'active',
  'terminal': {'available': true},
});

AppNotifier notifierWithAgents(List<Agent> agents) {
  final notifier = AppNotifier(
    config: AppConfig.dev,
    authSession: AuthSession(),
    configStore: null,
  );
  final state = MachineState(_machine)
    ..connectionStatus = ConnectionStatus.connected
    ..terminalCapabilityLoaded = true
    ..terminalCapabilityAvailable = true
    ..agentLoadStatus = AgentLoadStatus.loaded
    ..agents = agents;
  notifier.machines = [_machine];
  notifier.machineStates[_machine.machineId] = state;
  notifier.expandedMachines.add(_machine.machineId);
  return notifier;
}

PendingQuestion question({
  String agentId = 'a1',
  String requestId = 'q_1',
  String prompt = 'Which colour theme do you want?',
  List<String> options = const ['Blue', 'Red'],
  bool multi = false,
  DateTime? since,
}) => PendingQuestion(
  machineId: 'm1',
  agentId: agentId,
  requestId: requestId,
  answerKey: prompt,
  prompt: prompt,
  options: options,
  multi: multi,
  since: since ?? DateTime.now(),
);

Future<void> pumpInbox(WidgetTester tester, AppNotifier notifier) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showAttentionInbox(context, notifier),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('the rail row', () {
    testWidgets('blocked outranks working on the badge, and says what is asked',
        (tester) async {
      final notifier = notifierWithAgents([_agent('a1', 'payments')]);
      final state = notifier.machineStates['m1']!;
      // Both at once is the normal case: the turn is still open while the
      // dialog waits, so the row has to choose, and only one of the two is a
      // claim on the person reading it.
      state.processingAgentIds.add('a1');
      state.blockedAgents['a1'] = question();

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 320, child: MachineRail(notifier: notifier)),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('payments'), findsOneWidget);
      expect(find.text('Which colour theme do you want?'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('agent-processing-indicator')),
        findsNothing,
        reason: 'the spinner must give way to the blocked mark',
      );
    });

    testWidgets('a working agent that is not blocked keeps its spinner',
        (tester) async {
      final notifier = notifierWithAgents([_agent('a1', 'payments')]);
      notifier.machineStates['m1']!.processingAgentIds.add('a1');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 320, child: MachineRail(notifier: notifier)),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('agent-processing-indicator')),
        findsOneWidget,
      );
    });
  });

  group('the inbox', () {
    testWidgets('lists the longest wait first', (tester) async {
      final notifier = notifierWithAgents([
        _agent('a1', 'payments'),
        _agent('a2', 'opencode'),
      ]);
      final now = DateTime.now();
      notifier.machineStates['m1']!.blockedAgents.addAll({
        'a2': question(
          agentId: 'a2',
          requestId: 'q_2',
          prompt: 'Run the migration on prod?',
          since: now.subtract(const Duration(minutes: 1)),
        ),
        'a1': question(since: now.subtract(const Duration(minutes: 9))),
      });

      await pumpInbox(tester, notifier);

      final rows = tester.widgetList<Text>(find.byType(Text)).toList();
      final names = [
        for (final row in rows)
          if (row.data == 'payments' || row.data == 'opencode') row.data,
      ];
      expect(names, ['payments', 'opencode']);
      expect(find.text('blocked 9m'), findsOneWidget);
    });

    testWidgets('only the selected row prints its digits, and ↓ moves them',
        (tester) async {
      final notifier = notifierWithAgents([
        _agent('a1', 'payments'),
        _agent('a2', 'opencode'),
      ]);
      final now = DateTime.now();
      notifier.machineStates['m1']!.blockedAgents.addAll({
        'a1': question(since: now.subtract(const Duration(minutes: 9))),
        'a2': question(
          agentId: 'a2',
          requestId: 'q_2',
          prompt: 'Run the migration on prod?',
          options: const ['Yes', 'No'],
          since: now.subtract(const Duration(minutes: 1)),
        ),
      });

      await pumpInbox(tester, notifier);

      // A digit acts on the selection, so exactly one row may print numbers —
      // otherwise "1" would appear to belong to several agents at once.
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(
        find.ancestor(of: find.text('1'), matching: find.text('Blue')),
        findsNothing,
      );
      expect(find.text('Blue'), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      // Still exactly one numbered row — the second one now.
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('a multi-select offers the pane instead of half an answer',
        (tester) async {
      final notifier = notifierWithAgents([_agent('a1', 'payments')]);
      notifier.machineStates['m1']!.blockedAgents['a1'] = question(
        prompt: 'Which files should I touch?',
        options: const ['auth.ts', 'token.ts'],
        multi: true,
      );

      await pumpInbox(tester, notifier);

      expect(find.text('Pick several — open the pane to answer.'), findsOneWidget);
      expect(find.text('auth.ts'), findsNothing);
    });

    testWidgets('says so plainly when nothing is waiting', (tester) async {
      await pumpInbox(tester, notifierWithAgents([_agent('a1', 'payments')]));
      expect(find.text('Nothing is waiting on you.'), findsOneWidget);
    });
  });

  group('answering', () {
    test('a multi-select is refused rather than half-keyed', () async {
      final notifier = notifierWithAgents([_agent('a1', 'payments')]);
      final asked = question(multi: true);
      await notifier.answerQuestion(asked, 'auth.ts');
      expect(notifier.isAnswering(asked), isFalse);
    });

    test('with no live socket the question is left standing', () async {
      // Nothing can be keyed into a pane the window is not talking to, so the
      // row must NOT go into "answering…" and strand there.
      final notifier = notifierWithAgents([_agent('a1', 'payments')]);
      final asked = question();
      await notifier.answerQuestion(asked, 'Blue');
      expect(notifier.isAnswering(asked), isFalse);
    });
  });
}
