import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/auth/cli_link.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/models.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/widgets/link_machine_screen.dart';

class _FakeCliLink implements CliLink {
  final Future<CliLinkImportResult> Function(String token) onImport;
  _FakeCliLink(this.onImport);

  @override
  Future<CliLinkImportResult> import(String token) => onImport(token);

  @override
  Future<CliLinkCreateResult> create() async => const CliLinkCreateResult();

  @override
  Future<CliLinkListResult> list() async => const CliLinkListResult();

  @override
  Future<String?> unlink(String machineId) async => null;
}

void main() {
  const machine = Machine(
    machineId: 'remote-1',
    apiKey: '',
    authMode: MachineAuthMode.remote,
    name: 'remote-mac',
    status: 'online',
  );

  AppNotifier notifierFor(_FakeCliLink cliLink) {
    final notifier = AppNotifier(
      config: AppConfig.dev,
      authSession: AuthSession(),
      configStore: null,
      cliLink: cliLink,
    );
    notifier.machines = [machine];
    notifier.machineStates[machine.machineId] = MachineState(machine)
      ..needsLink = true
      ..agentLoadStatus = AgentLoadStatus.needsLink;
    return notifier;
  }

  testWidgets('shows a clear three-step guide for the target machine', (
    tester,
  ) async {
    final notifier = notifierFor(
      _FakeCliLink((_) async => const CliLinkImportResult()),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LinkMachineScreen(
            notifier: notifier,
            machineState: notifier.machineStates[machine.machineId]!,
          ),
        ),
      ),
    );

    expect(find.text('Link this machine'), findsOneWidget);
    expect(
      find.text(
        'remote-mac is online, but it is not linked to this computer yet.',
      ),
      findsOneWidget,
    );
    expect(find.text('On remote-mac, open Harness.'), findsOneWidget);
    expect(
      find.text('Go to the account menu and generate a code'),
      findsOneWidget,
    );
    expect(find.text('Paste the code here'), findsOneWidget);
    expect(find.text('Copy the code it shows you.'), findsOneWidget);
    expect(find.textContaining('Account'), findsOneWidget);
    expect(find.textContaining('Remote into another machine…'), findsOneWidget);
    expect(find.textContaining('Generate'), findsOneWidget);
    expect(find.text('Paste code from remote-mac'), findsOneWidget);
    expect(find.text('Link machine'), findsOneWidget);
    expect(
      find.text(
        'Your previous agent will reconnect automatically after linking.',
      ),
      findsOneWidget,
    );
    expect(find.text('Machine ID: remote-1'), findsNothing);

    await tester.tap(find.byKey(const Key('link-troubleshooting-details')));
    await tester.pump();
    expect(find.text('Machine ID: remote-1'), findsOneWidget);

    // Close sits bottom-right as a text button, matching every other dialog in the app —
    // not a floating top-right × icon.
    expect(find.text('Close'), findsOneWidget);
    notifier.dispose();
  });

  testWidgets('tapping Close dismisses the link prompt', (tester) async {
    final notifier = notifierFor(
      _FakeCliLink((_) async => const CliLinkImportResult()),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LinkMachineScreen(
            notifier: notifier,
            machineState: notifier.machineStates[machine.machineId]!,
          ),
        ),
      ),
    );

    expect(notifier.isLinkPromptDismissed(machine.machineId), isFalse);
    await tester.tap(find.text('Close'));
    await tester.pump();
    expect(notifier.isLinkPromptDismissed(machine.machineId), isTrue);
    notifier.dispose();
  });

  testWidgets(
    'submitting a token calls importLinkToken and clears needsLink on success',
    (tester) async {
      String? importedToken;
      final notifier = notifierFor(
        _FakeCliLink((token) async {
          importedToken = token;
          return CliLinkImportResult(linkedMachineId: machine.machineId);
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LinkMachineScreen(
              notifier: notifier,
              machineState: notifier.machineStates[machine.machineId]!,
            ),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('link-token-field')),
        'tok_abc123',
      );
      await tester.tap(find.byKey(const Key('link-import-button')));
      await tester.pumpAndSettle();

      expect(importedToken, 'tok_abc123');
      expect(notifier.machineStates[machine.machineId]!.needsLink, isFalse);
      notifier.dispose();
    },
  );

  testWidgets('shows the CLI error inline and keeps needsLink on failure', (
    tester,
  ) async {
    final notifier = notifierFor(
      _FakeCliLink(
        (_) async => const CliLinkImportResult(
          error: 'That token is invalid, expired, or missing a machine id.',
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LinkMachineScreen(
            notifier: notifier,
            machineState: notifier.machineStates[machine.machineId]!,
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('link-token-field')),
      'bad-token',
    );
    await tester.tap(find.byKey(const Key('link-import-button')));
    await tester.pumpAndSettle();

    expect(
      find.text('That token is invalid, expired, or missing a machine id.'),
      findsOneWidget,
    );
    expect(notifier.machineStates[machine.machineId]!.needsLink, isTrue);
    notifier.dispose();
  });
}
