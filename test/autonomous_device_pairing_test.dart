import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/autonomous_device/autonomous_device_cli.dart';
import 'package:harness/shared/widgets/app_icon_button.dart';
import 'package:harness/shared/widgets/skeleton.dart';
import 'package:harness/settings/sections/devices_section.dart';

class FakeAutonomousDeviceCli extends AutonomousDeviceCli {
  bool paired = false;
  int statusCalls = 0;
  Duration window = const Duration(seconds: 60);
  Map<String, dynamic> pairState = {'state': 'idle'};
  Completer<void>? statusWait;
  bool unsupported = false;
  final replacements = <bool>[];
  final submissions = <Map<String, dynamic>>[];
  int expiry = DateTime.now()
      .add(const Duration(seconds: 60))
      .millisecondsSinceEpoch;
  final revoked = <String>[];
  @override
  Future<Map<String, dynamic>> status() async {
    statusCalls++;
    if (statusWait != null) await statusWait!.future;
    if (unsupported) {
      throw const AutonomousDeviceCliException('NOT_FOUND', 'Unsupported CLI');
    }
    return {'proto': 1, 'address': '192.168.1.10:18474'};
  }

  @override
  Future<Map<String, dynamic>> list() async => {
    'devices': [
      if (paired)
        {
          'id': 'device-public-key',
          'label': 'Kitchen',
          'online': false,
          'fingerprint': 'ABCD 1234',
        },
    ],
  };
  @override
  Future<Map<String, dynamic>> pairStatus() async => pairState;
  @override
  Future<Map<String, dynamic>> listen({bool replace = false}) async {
    replacements.add(replace);
    return {
      'state': 'listening',
      'address': '192.168.1.10:18474',
      'expiresAt': expiry = DateTime.now().add(window).millisecondsSinceEpoch,
      'machineName': 'My computer',
    };
  }

  @override
  Future<Map<String, dynamic>> pair({
    required String code,
    required String pairId,
    bool replace = false,
  }) async {
    submissions.add({'code': code, 'pairId': pairId, 'replace': replace});
    return {'state': 'running'};
  }

  @override
  Future<Map<String, dynamic>> cancel() async => {'cancelled': true};

  @override
  Future<Map<String, dynamic>> revoke(String id) async {
    revoked.add(id);
    paired = false;
    return {'revoked': 1};
  }
}

void main() {
  Future<void> open(WidgetTester tester, FakeAutonomousDeviceCli cli) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DevicesSection(cli: cli)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('listen shows address and asks the device to generate its code', (
    tester,
  ) async {
    final cli = FakeAutonomousDeviceCli();
    await open(tester, cli);
    await tester.tap(find.text('Pair an Autonomous device'));
    await tester.pumpAndSettle();
    expect(cli.replacements, [false]);
    expect(find.byKey(const Key('autonomous-device-code')), findsNothing);
    expect(find.text('192.168.1.10:18474'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('replacement requires explicit confirmation', (tester) async {
    final cli = FakeAutonomousDeviceCli()..paired = true;
    await open(tester, cli);
    expect(find.text('Paired · Offline'), findsOneWidget);
    await tester.tap(find.text('Replace Autonomous device'));
    await tester.pumpAndSettle();
    expect(cli.replacements, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(cli.replacements, isEmpty);
    await tester.tap(find.text('Replace Autonomous device'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('device-confirm')));
    await tester.pumpAndSettle();
    expect(cli.replacements, [true]);
    expect(find.text('Kitchen'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'unsupported CLI offers update guidance without pairing actions',
    (tester) async {
      await open(tester, FakeAutonomousDeviceCli()..unsupported = true);
      expect(
        find.text('Update Harness CLI to use Autonomous devices.'),
        findsOneWidget,
      );
      expect(find.text('Unsupported CLI'), findsNothing);
      expect(find.text('Pair an Autonomous device'), findsNothing);
      expect(find.text('Refresh'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('default construction never calls the real CLI in tests', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DevicesSection())),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 2));
    expect(tester.takeException(), isNull);
    final refresh = tester.widget<AppIconButton>(find.byType(AppIconButton));
    expect(refresh.onPressed, isNull);
  });

  test('real AutonomousDeviceCli refuses commands in tests', () async {
    await expectLater(
      AutonomousDeviceCli().status(),
      throwsA(isA<AutonomousDeviceCliException>()),
    );
  });

  testWidgets('injected CLI does not start background polling in tests', (
    tester,
  ) async {
    final cli = FakeAutonomousDeviceCli();
    await open(tester, cli);
    await tester.pump(const Duration(minutes: 2));
    expect(cli.statusCalls, 1);
  });

  testWidgets('first fetch shows a skeleton then replaces it with state', (
    tester,
  ) async {
    final pending = Completer<void>();
    final cli = FakeAutonomousDeviceCli()..statusWait = pending;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DevicesSection(cli: cli)),
      ),
    );
    await tester.pump();
    expect(find.byType(SkeletonBlock), findsOneWidget);
    expect(find.text('No Autonomous device paired'), findsNothing);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(SkeletonBlock), findsNothing);
    expect(find.text('No Autonomous device paired'), findsOneWidget);
  });

  testWidgets('device intent reveals code input and submits the exact intent', (
    tester,
  ) async {
    final cli = FakeAutonomousDeviceCli();
    await open(tester, cli);
    await tester.tap(find.text('Pair an Autonomous device'));
    await tester.pumpAndSettle();
    cli.pairState = {
      'state': 'waiting',
      'pairId': 'intent-1',
      'deviceLabel': 'My Autonomous device',
      'expiresAt': cli.expiry,
    };
    await tester.ensureVisible(find.byType(AppIconButton));
    await tester.tap(find.byType(AppIconButton));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('autonomous-device-code'));
    await tester.ensureVisible(field);
    await tester.enterText(field, 'abc234');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(cli.submissions, [
      {'code': 'ABC234', 'pairId': 'intent-1', 'replace': false},
    ]);
    expect(find.byKey(const Key('autonomous-device-code')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('stale intent refuses submission without sending a code', (
    tester,
  ) async {
    final cli = FakeAutonomousDeviceCli();
    cli.pairState = {
      'state': 'waiting',
      'pairId': 'old',
      'expiresAt': cli.expiry,
    };
    await open(tester, cli);
    final field = find.byKey(const Key('autonomous-device-code'));
    await tester.ensureVisible(field);
    await tester.enterText(field, 'ABC234');
    cli.pairState = {
      'state': 'waiting',
      'pairId': 'new',
      'expiresAt': cli.expiry,
    };
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(cli.submissions, isEmpty);
    expect(find.textContaining('The pairing request changed.'), findsOneWidget);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('polling a different intent clears typed code', (tester) async {
    final cli = FakeAutonomousDeviceCli();
    cli.pairState = {
      'state': 'waiting',
      'pairId': 'old',
      'expiresAt': cli.expiry,
    };
    await open(tester, cli);
    final field = find.byKey(const Key('autonomous-device-code'));
    await tester.ensureVisible(field);
    await tester.enterText(field, 'ABC234');
    cli.pairState = {
      'state': 'waiting',
      'pairId': 'new',
      'expiresAt': cli.expiry,
    };
    await tester.ensureVisible(find.byType(AppIconButton));
    await tester.tap(find.byType(AppIconButton));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'terminal status clears entered code and never displays a returned code',
    (tester) async {
      final cli = FakeAutonomousDeviceCli();
      cli.pairState = {
        'state': 'waiting',
        'pairId': 'intent-1',
        'expiresAt': cli.expiry,
        'code': 'WRONG1',
      };
      await open(tester, cli);
      final field = find.byKey(const Key('autonomous-device-code'));
      final controller = tester.widget<TextField>(field).controller!;
      expect(controller.text, isEmpty);
      expect(find.text('WRONG1'), findsNothing);
      await tester.ensureVisible(field);
      await tester.enterText(field, 'ABC234');
      cli.pairState = {'state': 'paired', 'deviceFingerprint': '1234'};
      await tester.ensureVisible(find.byType(AppIconButton));
      await tester.tap(find.byType(AppIconButton));
      await tester.pumpAndSettle();
      expect(controller.text, isEmpty);
      expect(find.byKey(const Key('autonomous-device-code')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('code is passed exclusively as stdin, never CLI arguments', () async {
    final cli = RecordingAutonomousDeviceCli();
    await cli.pair(code: 'ABC234', pairId: 'intent-1', replace: true);
    expect(cli.operation, 'pair');
    expect(cli.arguments, [
      '--code-stdin',
      '--pair-id',
      'intent-1',
      '--replace',
    ]);
    expect(cli.arguments.join(' '), isNot(contains('ABC234')));
    expect(cli.secret, 'ABC234');
  });
}

class RecordingAutonomousDeviceCli extends AutonomousDeviceCli {
  String? operation;
  List<String> arguments = [];
  String? secret;
  @override
  Future<Map<String, dynamic>> command(
    String operation, {
    List<String> arguments = const [],
    String? secretStdin,
  }) async {
    this.operation = operation;
    this.arguments = arguments;
    secret = secretStdin;
    return {'state': 'running'};
  }
}
