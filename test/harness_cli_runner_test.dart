import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/cli_link.dart';
import 'package:harness/core/harness_cli_runner.dart';

void main() {
  late Directory scratch;

  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('harness-cli-runner-');
  });

  tearDown(() async {
    if (await scratch.exists()) await scratch.delete(recursive: true);
  });

  test(
    'uses the managed Node runtime and CLI bundle without a shell',
    () async {
      final home = Directory('${scratch.path}/home')..createSync();
      final harnessHome = Directory('${home.path}/.harness')..createSync();
      final node = File('${harnessHome.path}/runtime/node-v22/bin/node')
        ..createSync(recursive: true);
      File('${harnessHome.path}/runtime/current-node')
        ..createSync(recursive: true)
        ..writeAsStringSync('${node.path}\n');
      final cli = File('${harnessHome.path}/cli/cli.js')
        ..createSync(recursive: true);

      final invocation = await HarnessCliRunner(
        harnessHome: harnessHome,
        environment: {'HOME': home.path, 'PATH': '/usr/bin'},
      ).resolve(['link', 'create']);

      expect(invocation.source, HarnessCliSource.managed);
      expect(invocation.executable, node.path);
      expect(invocation.arguments, [cli.path, 'link', 'create']);
      expect(invocation.executable, isNot(contains('zsh')));
      expect(
        invocation.environment['PATH'],
        '${home.path}/.local/bin:/usr/bin',
      );
    },
  );

  test('uses the explicit legacy launcher before PATH', () async {
    final home = Directory('${scratch.path}/home')..createSync();
    final harnessHome = Directory('${home.path}/.harness')..createSync();
    final launcher = File('${home.path}/.local/bin/harness')
      ..createSync(recursive: true);

    final invocation = await HarnessCliRunner(
      harnessHome: harnessHome,
      environment: {'HOME': home.path, 'PATH': '/usr/bin'},
    ).resolve(['start']);

    expect(invocation.source, HarnessCliSource.launcher);
    expect(invocation.executable, launcher.path);
    expect(invocation.arguments, ['start']);
  });

  test(
    'link Generate invokes cli.js as direct argv and reads its token',
    () async {
      final home = Directory('${scratch.path}/home')..createSync();
      final harnessHome = Directory('${home.path}/.harness')..createSync();
      final node = File('${harnessHome.path}/runtime/node-v22/bin/node')
        ..createSync(recursive: true);
      File('${harnessHome.path}/runtime/current-node')
        ..createSync(recursive: true)
        ..writeAsStringSync('${node.path}\n');
      final cli = File('${harnessHome.path}/cli/cli.js')
        ..createSync(recursive: true);
      String? executable;
      List<String>? arguments;

      final result = await CliLink(
        runner: HarnessCliRunner(
          harnessHome: harnessHome,
          environment: {'HOME': home.path, 'PATH': '/usr/bin'},
          runProcess: (command, argv, {environment}) async {
            executable = command;
            arguments = argv;
            return ProcessResult(
              42,
              0,
              'Machine-link token (valid for 7 days):\n\n  tok_abc\n\n'
                  'fingerprint  1234ABCD\n',
              '',
            );
          },
        ),
      ).create();

      expect(executable, node.path);
      expect(arguments, [cli.path, 'link', 'create']);
      expect(result.error, isNull);
      expect(result.token, 'tok_abc');
      expect(result.fingerprint, '1234ABCD');
    },
  );
}
