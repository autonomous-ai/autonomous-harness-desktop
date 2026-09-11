import 'package:flutter_test/flutter_test.dart';
import 'package:harness/e2ee/keys.dart';
import 'package:harness/viewer/password_link.dart';

import 'fake_relay_machine.dart';

const _machineId = 'machine-1';

void main() {
  late E2eeIdentity machineIdentity;
  late E2eeIdentity deviceIdentity;
  final machines = <FakeRelayMachine>[];

  setUpAll(() async {
    machineIdentity = await E2eeIdentity.generate();
    deviceIdentity = await E2eeIdentity.generate();
  });

  tearDown(() async {
    for (final machine in machines) {
      await machine.close();
    }
    machines.clear();
  });

  Future<(FakeRelayMachine, PasswordLinkResult, List<PasswordLinkStage>)> link(
    String typed, {
    String? selectError,
  }) async {
    final machine = await FakeRelayMachine.start(
      machineId: _machineId,
      identity: machineIdentity,
      password: 'correct horse',
      selectError: selectError,
    );
    machines.add(machine);
    final stages = <PasswordLinkStage>[];
    final result = await linkWithPassword(
      machineId: _machineId,
      password: typed,
      identity: deviceIdentity,
      accessToken: 'tok',
      wsBaseUrl: machine.wsBaseUrl,
      autonomousEnv: 'prod',
      onProgress: stages.add,
    );
    return (machine, result, stages);
  }

  test(
    'the right password pins the machine and hands over this device',
    () async {
      final (machine, result, stages) = await link('correct horse');
      final linked = result as PasswordLinked;
      expect(linked.peerPub, machineIdentity.pub);
      expect(linked.fingerprint, fingerprint(machineIdentity.pub));
      expect(machine.linkedPub, deviceIdentity.pub);
      expect(machine.protocols, ['tok']);
      expect(stages, PasswordLinkStage.values);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'a wrong password is refused as one, and pins nothing',
    () async {
      final (machine, result, _) = await link('wrong horse');
      expect((result as PasswordLinkFailed).code, 'WRONG_PASSWORD');
      expect(machine.linkedPub, isNull);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('a machine the relay cannot reach says why', () async {
    final (_, result, stages) = await link(
      'correct horse',
      selectError: 'MACHINE_OFFLINE',
    );
    expect((result as PasswordLinkFailed).code, 'MACHINE_OFFLINE');
    expect(stages, [PasswordLinkStage.connecting]);
  });
}
