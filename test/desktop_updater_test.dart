import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/update/desktop_updater.dart';

Future<String> _sha256Hex(List<int> bytes) async {
  final hash = await Sha256().hash(bytes);
  return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Why the macOS half of this file is host-gated.
///
/// `ditto` is macOS-only, and so is the branch it stands in for: unpacking a
/// `.app` and reading its Info.plist. A Linux host — the only host that can
/// build a Linux release, so the one a Linux release is cut on — cannot build
/// that archive at all. Rather than fail the whole file there (which is what it
/// did: 21 of these, every Linux-packaging test included, died in the shared
/// `setUp`), the macOS bundle is built only on macOS, the two tests that
/// actually unpack one are skipped elsewhere, and everything that just needs
/// *some* bytes with a known size and hash gets [_fakeArchiveBytes]. The rest
/// names the branch it means (`isLinux:`) instead of inheriting the host's.
final String? _macOnly = Platform.isMacOS
    ? null
    : 'needs a macOS host: `ditto` builds the .app archive this unpacks';

/// Stand-in bytes for a host with no `ditto`.
///
/// Enough for anything that only serves the archive over HTTP and checks its
/// length or sha256 — a manifest entry, a mismatched-hash rejection. Nothing
/// unpacks it.
Future<(List<int>, String)> _fakeArchiveBytes(String version) async {
  final bytes = utf8.encode('not-a-real-bundle:$version\n' * 8);
  return (bytes, await _sha256Hex(bytes));
}

/// Builds a real, tiny `.app`-shaped bundle at [dir]/Harness.app with the given version stamped into
/// its Info.plist, zips it with the same `ditto` invocation the upload script uses, and returns
/// (zipBytes, sha256Hex).
Future<(List<int>, String)> _buildFakeBundleZip(Directory dir, String version) async {
  final bundle = Directory('${dir.path}/Harness.app/Contents')
    ..createSync(recursive: true);
  File('${bundle.path}/Info.plist').writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleShortVersionString</key>
	<string>$version</string>
</dict>
</plist>
''');
  final zipPath = '${dir.path}/Harness-macos.zip';
  final result = await Process.run('/usr/bin/ditto', [
    '-c', '-k', '--sequesterRsrc', '--keepParent',
    'Harness.app', 'Harness-macos.zip',
  ], workingDirectory: dir.path);
  expect(result.exitCode, 0, reason: 'ditto failed: ${result.stderr}');
  final bytes = File(zipPath).readAsBytesSync();
  return (bytes, await _sha256Hex(bytes));
}

/// Builds a real Linux-shaped bundle at [dir]/Harness/{harness,version.txt} — the flat layout
/// `scripts/upload-desktop-linux.sh` packages — tars it with the same `tar` invocation that script
/// uses, and returns (tarGzBytes, sha256Hex). `tar` (unlike `ditto`/`plutil`) exists on every dev
/// machine, so this exercises the real Linux unpack/version-check path even from a macOS test host.
Future<(List<int>, String)> _buildFakeLinuxBundleTarGz(
  Directory dir,
  String version,
) async {
  final bundle = Directory('${dir.path}/Harness')..createSync(recursive: true);
  File('${bundle.path}/harness').writeAsStringSync('#!/bin/sh\necho fake harness\n');
  File('${bundle.path}/version.txt').writeAsStringSync(version);
  final tarPath = '${dir.path}/Harness-linux-x64.tar.gz';
  final result = await Process.run('/usr/bin/tar', [
    '-czf', 'Harness-linux-x64.tar.gz',
    'Harness',
  ], workingDirectory: dir.path);
  expect(result.exitCode, 0, reason: 'tar failed: ${result.stderr}');
  final bytes = File(tarPath).readAsBytesSync();
  return (bytes, await _sha256Hex(bytes));
}

void main() {
  late Directory scratch;
  HttpServer? server;
  late List<int> zipBytes;
  late String zipSha;
  const newVersion = '9.9.9';

  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('desktop-updater-');
    final (bytes, sha) = Platform.isMacOS
        ? await _buildFakeBundleZip(scratch, newVersion)
        : await _fakeArchiveBytes(newVersion);
    zipBytes = bytes;
    zipSha = sha;
  });

  tearDown(() async {
    await server?.close(force: true);
    server = null;
    if (await scratch.exists()) await scratch.delete(recursive: true);
  });

  /// Serves `/metadata.json` (the `desktop-macos` entry) and `/Harness-macos.zip` from a loopback
  /// server, and returns the manifest URL a [DesktopUpdater] should be pointed at.
  Future<String> serveMetadataAndZip({
    required String manifestVersion,
    String? shaOverride,
    int? sizeOverride,
  }) async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = 'http://127.0.0.1:${server!.port}';
    server!.listen((request) async {
      if (request.uri.path == '/metadata.json') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'desktop-macos': {
            'version': manifestVersion,
            'url': '$base/Harness-macos.zip',
            'sha256': shaOverride ?? zipSha,
            'size': sizeOverride ?? zipBytes.length,
          },
        }));
      } else if (request.uri.path == '/Harness-macos.zip') {
        request.response.add(zipBytes);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    return '$base/metadata.json';
  }

  test('checkOnce returns the entry when the manifest is strictly newer', () async {
    final url = await serveMetadataAndZip(manifestVersion: newVersion);
    final updater = DesktopUpdater(dio: Dio(), isLinux: false, metadataUrl: url, releaseMode: true);
    final info = await updater.checkOnce(currentVersion: '1.0.0');
    expect(info, isNotNull);
    expect(info!.version, newVersion);
    expect(info.sha256, zipSha);
    expect(info.size, zipBytes.length);
  });

  test('checkOnce never reports an update outside release mode (debug/profile builds)', () async {
    final url = await serveMetadataAndZip(manifestVersion: newVersion);
    // No releaseMode override — defaults to kReleaseMode, which is false under `flutter test`.
    final updater = DesktopUpdater(dio: Dio(), isLinux: false, metadataUrl: url);
    expect(await updater.checkOnce(currentVersion: '1.0.0'), isNull);

    final explicitlyOff = DesktopUpdater(
      dio: Dio(),
      isLinux: false,
      metadataUrl: url,
      releaseMode: false,
    );
    expect(await explicitlyOff.checkOnce(currentVersion: '1.0.0'), isNull);
  });

  test(
    'checkOnce marks a major/minor bump forced, and a same-major.minor patch bump forced past the drift limit',
    () async {
      final url = await serveMetadataAndZip(manifestVersion: newVersion); // 9.9.9
      final updater = DesktopUpdater(dio: Dio(), isLinux: false, metadataUrl: url, releaseMode: true);

      final minorBump = await updater.checkOnce(currentVersion: '9.8.9');
      expect(minorBump, isNotNull);
      expect(minorBump!.forced, isTrue);

      final majorBump = await updater.checkOnce(currentVersion: '8.9.9');
      expect(majorBump, isNotNull);
      expect(majorBump!.forced, isTrue);

      final withinDrift = await updater.checkOnce(currentVersion: '9.9.5');
      expect(withinDrift, isNotNull);
      expect(withinDrift!.forced, isFalse);

      final beyondDrift = await updater.checkOnce(currentVersion: '9.9.3');
      expect(beyondDrift, isNotNull);
      expect(beyondDrift!.forced, isTrue);
    },
  );

  test('isForcedUpdate is true for a major/minor difference', () {
    expect(isForcedUpdate('2.0.0', '1.9.9'), isTrue);
    expect(isForcedUpdate('1.3.0', '1.2.9'), isTrue);
    expect(isForcedUpdate('1.2.4', '1.2.3'), isFalse);
    expect(isForcedUpdate('1.2.3', '1.2.3'), isFalse);
    expect(isForcedUpdate('not-a-version', '1.0.0'), isFalse);
  });

  test(
    'isForcedUpdate is also true for a same-major.minor patch drift beyond 5, false at or under it',
    () {
      expect(isForcedUpdate('1.2.2', '1.2.2'), isFalse); // no drift
      expect(isForcedUpdate('1.2.7', '1.2.2'), isFalse); // drift 5, at the limit — still optional
      expect(isForcedUpdate('1.2.8', '1.2.2'), isTrue); // drift 6 — forced
      // A major/minor difference already forces it regardless of how small the patch drift is.
      expect(isForcedUpdate('1.3.0', '1.2.99'), isTrue);
    },
  );

  test('checkOnce returns null when the running version is already current or newer', () async {
    final url = await serveMetadataAndZip(manifestVersion: '1.0.0');
    final updater = DesktopUpdater(dio: Dio(), isLinux: false, metadataUrl: url, releaseMode: true);
    expect(await updater.checkOnce(currentVersion: '1.0.0'), isNull);
    expect(await updater.checkOnce(currentVersion: '2.0.0'), isNull);
  });

  test('checkOnce returns null (not an error) when the manifest is unreachable', () async {
    final updater = DesktopUpdater(
      dio: Dio(),
      isLinux: false,
      metadataUrl: 'http://127.0.0.1:1/metadata.json', // nothing listens here
      releaseMode: true,
    );
    expect(await updater.checkOnce(currentVersion: '1.0.0'), isNull);
  });

  test('checkOnce also treats unavailable package metadata as no update', () async {
    final updater = DesktopUpdater(
      dio: Dio(),
      isLinux: false,
      metadataUrl: 'http://127.0.0.1:1/metadata.json',
      releaseMode: true,
    );
    // Widget/unit tests have no package_info platform channel. The startup
    // checker must not leave an unhandled asynchronous exception in that case.
    expect(await updater.checkOnce(), isNull);
  });

  test('semverGt is strict and ignores prerelease/build metadata', () {
    expect(semverGt('1.2.4', '1.2.3'), isTrue);
    expect(semverGt('2.0.0', '1.9.9'), isTrue);
    expect(semverGt('1.2.3', '1.2.3'), isFalse);
    expect(semverGt('1.2.3', '1.2.4'), isFalse);
    expect(semverGt('1.2.3-beta', '1.2.3'), isFalse);
    expect(semverGt('not-a-version', '1.0.0'), isFalse);
  });

  test('startChecking calls onUpdateAvailable only when a newer build exists', () async {
    final urlUpToDate = await serveMetadataAndZip(manifestVersion: '1.0.0');
    final noUpdates = <UpdateInfo>[];
    final t1 = DesktopUpdater(dio: Dio(), isLinux: false, metadataUrl: urlUpToDate, releaseMode: true).startChecking(
      interval: const Duration(days: 1),
      currentVersion: '1.0.0',
      onUpdateAvailable: noUpdates.add,
    );
    addTearDown(t1.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(noUpdates, isEmpty);

    await server?.close(force: true);
    server = null;
    final urlNewer = await serveMetadataAndZip(manifestVersion: newVersion);
    final found = <UpdateInfo>[];
    final t2 = DesktopUpdater(dio: Dio(), isLinux: false, metadataUrl: urlNewer, releaseMode: true).startChecking(
      interval: const Duration(days: 1),
      currentVersion: '1.0.0',
      onUpdateAvailable: found.add,
    );
    addTearDown(t2.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(found, hasLength(1));
    expect(found.single.version, newVersion);
  });

  test('downloadAndStage verifies sha256 before trusting the download', () async {
    await serveMetadataAndZip(manifestVersion: newVersion);
    final updater = DesktopUpdater(dio: Dio(), isLinux: false);
    final badInfo = UpdateInfo(
      version: newVersion,
      url: 'http://127.0.0.1:${server!.port}/Harness-macos.zip',
      sha256: '0' * 64,
      size: zipBytes.length,
    );
    final staged = await updater.downloadAndStage(badInfo);
    expect(staged, isNull);
  });

  test(
    'downloadAndStage unpacks and confirms the staged bundle really carries the advertised version',
    () async {
      await serveMetadataAndZip(manifestVersion: newVersion);
      final updater = DesktopUpdater(dio: Dio(), isLinux: false);
      final info = UpdateInfo(
        version: newVersion,
        url: 'http://127.0.0.1:${server!.port}/Harness-macos.zip',
        sha256: zipSha,
        size: zipBytes.length,
      );
      final staged = await updater.downloadAndStage(info);
      expect(staged, isNotNull);
      expect(staged!.version, newVersion);
      expect(Directory(staged.bundlePath).existsSync(), isTrue);
      await Directory(staged.stagingDirPath).delete(recursive: true);
    },
    skip: _macOnly,
  );

  test(
    'downloadAndStage rejects a bundle whose Info.plist does not match the advertised version',
    () async {
      await serveMetadataAndZip(manifestVersion: newVersion);
      final updater = DesktopUpdater(dio: Dio(), isLinux: false);
      // Real zip on disk is stamped $newVersion — advertise a different one.
      final mismatched = UpdateInfo(
        version: '1.2.3',
        url: 'http://127.0.0.1:${server!.port}/Harness-macos.zip',
        sha256: zipSha,
        size: zipBytes.length,
      );
      final staged = await updater.downloadAndStage(mismatched);
      expect(staged, isNull);
    },
    skip: _macOnly,
  );

  test('applyStaged spawns a detached command and never launches a real process', () async {
    final calls = <String>[];
    final updater = DesktopUpdater(
      // The macOS relaunch, asked for by name rather than inherited from the
      // host — the Linux one is the group at the bottom of this file, and both
      // deserve to run wherever the suite does.
      isLinux: false,
      launchDetached: (command) async => calls.add(command),
    );
    final staged = StagedUpdate(
      version: newVersion,
      bundlePath: '${scratch.path}/staged/Harness.app',
      stagingDirPath: '${scratch.path}/staged',
    );
    final ok = await updater.applyStaged(
      staged,
      selfPid: 12345,
      runningBundlePath: '/tmp/does-not-exist/Harness.app',
    );
    expect(ok, isTrue);
    expect(calls, hasLength(1));
    expect(calls.single, contains('kill -0 12345'));
    expect(calls.single, contains('/tmp/does-not-exist/Harness.app'));
    expect(calls.single, contains(staged.bundlePath));
    expect(calls.single, contains('open -n'));
    expect(calls.single, contains('pgrep -f'));
  });

  test(
    'applyStaged does nothing when the running bundle path cannot be resolved',
    () async {
      var called = false;
      final updater = DesktopUpdater(
        // Same as above: the macOS "not inside a .app" branch. On Linux every
        // executable has a parent directory, so the host's own answer would
        // never be the null this is about.
        isLinux: false,
        launchDetached: (command) async => called = true,
      );
      final staged = StagedUpdate(
        version: newVersion,
        bundlePath: '${scratch.path}/staged/Harness.app',
        stagingDirPath: '${scratch.path}/staged',
      );
      // The test runner's own executable is not inside a `.app` bundle, and no override is given, so
      // currentBundlePath() resolves to null — the same "cannot resolve" branch a real, non-.app-hosted
      // process (e.g. running via `flutter test`) would hit.
      final ok = await updater.applyStaged(staged, selfPid: 1);
      expect(ok, isFalse);
      expect(called, isFalse);
    },
  );

  test('currentBundlePath walks up to the enclosing .app', () {
    expect(
      currentBundlePath(
        '/Applications/Harness.app/Contents/MacOS/Harness',
        false, // isLinux — the .app walk, on whatever host runs the suite
      ),
      '/Applications/Harness.app',
    );
    expect(currentBundlePath('/usr/local/bin/some-tool', false), isNull);
  });

  test('currentBundlePath on Linux is just the executable\'s parent directory', () {
    expect(
      currentBundlePath(
        '/home/user/.local/opt/Harness/harness',
        true, // isLinux
      ),
      '/home/user/.local/opt/Harness',
    );
  });

  group('Linux packaging (desktop-linux-x64)', () {
    late List<int> tarBytes;
    late String tarSha;

    setUp(() async {
      final (bytes, sha) = await _buildFakeLinuxBundleTarGz(scratch, newVersion);
      tarBytes = bytes;
      tarSha = sha;
    });

    Future<String> serveLinuxMetadataAndTar({required String manifestVersion}) async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final base = 'http://127.0.0.1:${server!.port}';
      server!.listen((request) async {
        if (request.uri.path == '/metadata.json') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'desktop-linux-x64': {
              'version': manifestVersion,
              'url': '$base/Harness-linux-x64.tar.gz',
              'sha256': tarSha,
              'size': tarBytes.length,
            },
          }));
        } else if (request.uri.path == '/Harness-linux-x64.tar.gz') {
          request.response.add(tarBytes);
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });
      return '$base/metadata.json';
    }

    test('checkOnce reads the desktop-linux-x64 manifest entry', () async {
      final url = await serveLinuxMetadataAndTar(manifestVersion: newVersion);
      final updater = DesktopUpdater(
        dio: Dio(),
        metadataUrl: url,
        releaseMode: true,
        isLinux: true,
      );
      final info = await updater.checkOnce(currentVersion: '1.0.0');
      expect(info, isNotNull);
      expect(info!.version, newVersion);
      expect(info.sha256, tarSha);
    });

    test(
      'downloadAndStage untars and confirms the staged bundle carries the advertised version',
      () async {
        await serveLinuxMetadataAndTar(manifestVersion: newVersion);
        final updater = DesktopUpdater(dio: Dio(), isLinux: true);
        final info = UpdateInfo(
          version: newVersion,
          url: 'http://127.0.0.1:${server!.port}/Harness-linux-x64.tar.gz',
          sha256: tarSha,
          size: tarBytes.length,
        );
        final staged = await updater.downloadAndStage(info);
        expect(staged, isNotNull);
        expect(staged!.version, newVersion);
        expect(staged.bundlePath, endsWith('/Harness'));
        expect(File('${staged.bundlePath}/harness').existsSync(), isTrue);
        await Directory(staged.stagingDirPath).delete(recursive: true);
      },
    );

    test(
      'downloadAndStage rejects a Linux bundle whose version.txt does not match',
      () async {
        await serveLinuxMetadataAndTar(manifestVersion: newVersion);
        final updater = DesktopUpdater(dio: Dio(), isLinux: true);
        final mismatched = UpdateInfo(
          version: '1.2.3',
          url: 'http://127.0.0.1:${server!.port}/Harness-linux-x64.tar.gz',
          sha256: tarSha,
          size: tarBytes.length,
        );
        final staged = await updater.downloadAndStage(mismatched);
        expect(staged, isNull);
      },
    );

    test(
      'applyStaged on Linux execs the binary directly instead of `open -n`',
      () async {
        final calls = <String>[];
        final updater = DesktopUpdater(
          isLinux: true,
          launchDetached: (command) async => calls.add(command),
        );
        final staged = StagedUpdate(
          version: newVersion,
          bundlePath: '${scratch.path}/staged/Harness',
          stagingDirPath: '${scratch.path}/staged',
        );
        final ok = await updater.applyStaged(
          staged,
          selfPid: 12345,
          runningBundlePath: '/home/user/.local/opt/Harness',
        );
        expect(ok, isTrue);
        expect(calls, hasLength(1));
        expect(calls.single, contains('kill -0 12345'));
        expect(calls.single, contains('/home/user/.local/opt/Harness/harness'));
        expect(calls.single, contains('nohup'));
        expect(calls.single, isNot(contains('open -n')));
        expect(calls.single, contains('pgrep -f'));
      },
    );
  });
}
