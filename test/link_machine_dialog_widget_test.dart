import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/auth/cli_link.dart';
import 'package:harness/core/config.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/widgets/link_machine_dialog.dart';

class _FakeCliLink implements CliLink {
  final CliLinkCreateResult createResult;
  _FakeCliLink({this.createResult = const CliLinkCreateResult()});

  @override
  Future<CliLinkImportResult> import(String token) async =>
      const CliLinkImportResult();

  @override
  Future<CliLinkCreateResult> create() async => createResult;

  @override
  Future<CliLinkListResult> list() async => const CliLinkListResult();

  @override
  Future<String?> unlink(String machineId) async => null;
}

Future<void> _pumpDialog(WidgetTester tester, AppNotifier notifier) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showLinkMachineDialog(context, notifier),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  AppNotifier notifier({CliLinkCreateResult? createResult}) => AppNotifier(
    config: AppConfig.dev,
    authSession: AuthSession(),
    configStore: null,
    cliLink: _FakeCliLink(
      createResult: createResult ?? const CliLinkCreateResult(),
    ),
  );

  testWidgets('shows only the generate flow, pointing paste at the sidebar', (
    tester,
  ) async {
    final appNotifier = notifier();
    await _pumpDialog(tester, appNotifier);

    expect(find.text('Link another machine'), findsOneWidget);
    expect(find.text('Let another machine control this one'), findsOneWidget);
    expect(
      find.text('Click Generate below to create a code for this machine.'),
      findsOneWidget,
    );
    expect(
      find.text(
        "On the OTHER machine, select this machine in the sidebar (it'll "
        "show 'link required') and paste the code there.",
      ),
      findsOneWidget,
    );

    // The paste-to-link card moved to LinkMachineScreen — it must not be duplicated here.
    expect(find.text('Control another machine from here'), findsNothing);
    expect(find.byKey(const Key('link-token-field')), findsNothing);
    expect(find.byKey(const Key('link-import-button')), findsNothing);
    appNotifier.dispose();
  });

  testWidgets('generate button is right-aligned', (tester) async {
    final appNotifier = notifier();
    await _pumpDialog(tester, appNotifier);

    final align = tester.widget<Align>(
      find
          .ancestor(
            of: find.byKey(const Key('link-generate-button')),
            matching: find.byType(Align),
          )
          .first,
    );
    expect(align.alignment, Alignment.centerRight);
    appNotifier.dispose();
  });

  testWidgets('generating shows the code and keeps the steps visible', (
    tester,
  ) async {
    final appNotifier = notifier(
      createResult: const CliLinkCreateResult(
        token: 'tok_abc123',
        fingerprint: '1535·C035·9474·FE9D',
      ),
    );
    await _pumpDialog(tester, appNotifier);

    await tester.tap(find.byKey(const Key('link-generate-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('link-generate-button')), findsNothing);
    expect(find.text('Valid 7 days.'), findsOneWidget);
    // Steps stay put so the user still sees where to take the code next.
    expect(
      find.text('Click Generate below to create a code for this machine.'),
      findsOneWidget,
    );
    appNotifier.dispose();
  });
}
