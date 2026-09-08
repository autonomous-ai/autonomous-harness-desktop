import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/lamp/lamp_cli.dart';
import 'package:harness/shared/widgets/app_icon_button.dart';
import 'package:harness/shared/widgets/skeleton.dart';
import 'package:harness/settings/sections/devices_section.dart';

class FakeLampCli extends LampCli {
  bool paired = false;
  int statusCalls = 0;
  Duration window = const Duration(seconds: 60);
  Map<String, dynamic> pairState = {'state': 'idle'};
  Completer<void>? statusWait;
  bool unsupported = false;
  final replacements = <bool>[];
  final revoked = <String>[];
  @override
  Future<Map<String, dynamic>> status() async {
    statusCalls++;
    if (statusWait != null) await statusWait!.future;
    if (unsupported) {
      throw const LampCliException('NOT_FOUND', 'Unsupported CLI');
    }
    return {'proto': 1, 'address': '192.168.1.10:18474'};
  }

  @override
  Future<Map<String, dynamic>> list() async => {
    'lamps': [
      if (paired)
        {
          'id': 'lamp-public-key',
          'label': 'Kitchen',
          'online': false,
          'fingerprint': 'ABCD 1234',
        },
    ],
  };
  @override
  Future<Map<String, dynamic>> pairStatus() async => pairState;
  @override
  Future<Map<String, dynamic>> pair({bool replace = false}) async {
    replacements.add(replace);
    return {
      'code': 'ABC234',
      'address': '192.168.1.10:18474',
      'expiresAt': DateTime.now().add(window).millisecondsSinceEpoch,
      'machineName': 'My computer',
    };
  }

  @override
  Future<Map<String, dynamic>> revoke(String id) async {
    revoked.add(id);
    paired = false;
    return {'revoked': 1};
  }
}

void main() {
  Future<void> open(WidgetTester tester, FakeLampCli cli) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DevicesSection(cli: cli)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('pairing displays CLI code and reachable address', (
    tester,
  ) async {
    final cli = FakeLampCli();
    await open(tester, cli);
    await tester.tap(find.text('Pair a lamp'));
    await tester.pumpAndSettle();
    expect(cli.replacements, [false]);
    expect(find.text('ABC234'), findsOneWidget);
    expect(find.text('192.168.1.10:18474'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('replacement requires explicit confirmation', (tester) async {
    final cli = FakeLampCli()..paired = true;
    await open(tester, cli);
    expect(find.text('Paired · Offline'), findsOneWidget);
    await tester.tap(find.text('Replace lamp'));
    await tester.pumpAndSettle();
    expect(cli.replacements, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(cli.replacements, isEmpty);
    await tester.tap(find.text('Replace lamp'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lamp-confirm')));
    await tester.pumpAndSettle();
    expect(cli.replacements, [true]);
    expect(find.text('Kitchen'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'unsupported CLI offers update guidance without pairing actions',
    (tester) async {
      await open(tester, FakeLampCli()..unsupported = true);
      expect(
        find.text('Update Harness CLI to use lamp devices.'),
        findsOneWidget,
      );
      expect(find.text('Unsupported CLI'), findsNothing);
      expect(find.text('Pair a lamp'), findsNothing);
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

  test('real LampCli refuses commands in tests', () async {
    await expectLater(LampCli().status(), throwsA(isA<LampCliException>()));
  });

  testWidgets('injected CLI does not start background polling in tests', (
    tester,
  ) async {
    final cli = FakeLampCli();
    await open(tester, cli);
    await tester.pump(const Duration(minutes: 2));
    expect(cli.statusCalls, 1);
  });

  testWidgets('first fetch shows a skeleton then replaces it with state', (
    tester,
  ) async {
    final pending = Completer<void>();
    final cli = FakeLampCli()..statusWait = pending;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DevicesSection(cli: cli)),
      ),
    );
    await tester.pump();
    expect(find.byType(SkeletonBlock), findsOneWidget);
    expect(find.text('No lamp paired'), findsNothing);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(SkeletonBlock), findsNothing);
    expect(find.text('No lamp paired'), findsOneWidget);
  });

  testWidgets('CLI deadline and nullable status metadata are preserved', (
    tester,
  ) async {
    final cli = FakeLampCli()..window = const Duration(minutes: 3);
    await open(tester, cli);
    await tester.tap(find.text('Pair a lamp'));
    await tester.pumpAndSettle();
    final expiry = find.textContaining(
      RegExp(r'Expires in 1[67-8][0-9] seconds'),
    );
    expect(expiry, findsOneWidget);
    cli.pairState = {
      'state': 'waiting',
      'address': null,
      'machineName': null,
      'code': 'ABC234',
      'expiresAt': DateTime.now()
          .add(const Duration(minutes: 3))
          .millisecondsSinceEpoch,
    };
    await tester.ensureVisible(find.byType(AppIconButton));
    await tester.tap(find.byType(AppIconButton));
    await tester.pumpAndSettle();
    expect(find.text('192.168.1.10:18474'), findsOneWidget);
    expect(find.text('My computer'), findsOneWidget);
  });
}
