import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/app_version.dart';

/// Published by `scripts/upload-desktop.sh` (`make upload-desktop`) — see
/// `RELEASE.md` for the full publish-side design this mirrors.
const _defaultMetadataUrl =
    'https://storage.googleapis.com/s3-autonomous-upgrade-3/harness/desktop/metadata.json';

/// Override for testing against a scratch manifest without touching the real one — see RELEASE.md's
/// "Rolling out safely" section. Empty (the default) means "use the real manifest".
const _metadataUrlOverride = String.fromEnvironment('DESKTOP_UPDATE_METADATA_URL');

/// Must match OTA_KEY in scripts/upload-desktop.sh / scripts/upload-desktop-linux.sh.
const _otaKeyMacOS = 'desktop-macos';
const _otaKeyLinux = 'desktop-linux-x64';

String get _metadataUrl =>
    _metadataUrlOverride.isNotEmpty ? _metadataUrlOverride : _defaultMetadataUrl;

class UpdateInfo {
  final String version;
  final String url;
  final String sha256;
  final int size;

  /// True when this version differs from the running one in the major or minor component — see
  /// [isForcedUpdate]. A forced update must be installed; the UI offers no way to skip or dismiss it.
  final bool forced;

  const UpdateInfo({
    required this.version,
    required this.url,
    required this.sha256,
    required this.size,
    this.forced = false,
  });
}

/// A downloaded, sha256-verified, unpacked-and-version-confirmed build sitting in a temp directory,
/// not yet swapped into place.
class StagedUpdate {
  final String version;
  final String bundlePath; // .../Harness.app inside stagingDirPath
  final String stagingDirPath;

  const StagedUpdate({
    required this.version,
    required this.bundlePath,
    required this.stagingDirPath,
  });
}

/// Strict X.Y.Z compare, prerelease/build metadata ignored — same rule as the CLI's own
/// `semverGt` (cli/src/lib/selfUpdate.ts in the harness CLI repo), so publishing an old build can
/// never look newer than what's already running.
bool semverGt(String a, String b) {
  final x = _parseSemverCore(a);
  final y = _parseSemverCore(b);
  if (x == null || y == null) return false;
  for (var i = 0; i < 3; i++) {
    if (x[i] != y[i]) return x[i] > y[i];
  }
  return false;
}

/// A patch-only bump (Z in X.Y.Z) stays optional up to this many versions behind — past it, a
/// user who keeps skipping patch releases is forced to catch up too. `make upload-desktop`'s
/// default patch auto-bump increments Z by exactly 1 per release, so this is a release count.
const _forcedPatchDrift = 5;

/// True when [newer] differs from [current] in the major or minor component (must update), or is
/// on the same major.minor but more than [_forcedPatchDrift] patch releases behind (must catch up).
bool isForcedUpdate(String newer, String current) {
  final x = _parseSemverCore(newer);
  final y = _parseSemverCore(current);
  if (x == null || y == null) return false;
  if (x[0] != y[0] || x[1] != y[1]) return true;
  return x[2] - y[2] > _forcedPatchDrift;
}

List<int>? _parseSemverCore(String version) {
  final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(version);
  if (match == null) return null;
  return [
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  ];
}

String _singleQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";

/// Resolves the running build's install root.
///
/// On macOS this walks up from the running executable to the enclosing
/// `.app` bundle — `.../Harness.app/Contents/MacOS/Harness` -> `.../Harness.app`.
/// On Linux the packaged build (see `scripts/upload-desktop-linux.sh`) is a
/// flat directory — the `harness` executable, `lib/`, and `data/` all sit
/// directly inside it — so the bundle root is simply the executable's parent.
String? currentBundlePath([String? executablePath, bool? isLinux]) {
  final resolved = executablePath ?? Platform.resolvedExecutable;
  if (isLinux ?? Platform.isLinux) {
    return File(resolved).parent.path;
  }
  var dir = File(resolved).parent;
  for (var i = 0; i < 6; i++) {
    if (dir.path.endsWith('.app')) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) return null; // reached filesystem root
    dir = parent;
  }
  return null;
}

Future<void> _defaultLaunchDetached(String command) async {
  await Process.start(
    Platform.isLinux ? '/bin/bash' : '/bin/zsh',
    ['-l', '-c', command],
    mode: ProcessStartMode.detached,
  );
}

/// Checks the public GCS manifest for a newer desktop build than the one currently running,
/// downloads + verifies it, and — once the caller applies it — swaps it into place and relaunches.
/// See `RELEASE.md` for the publish side and the full design (why this doesn't
/// silently auto-restart like the CLI's own self-updater does).
class DesktopUpdater {
  final Dio _dio;
  final Future<void> Function(String command) _launchDetached;
  final String _metadataUrlForInstance;
  final bool _releaseMode;
  final bool _isLinux;

  DesktopUpdater({
    Dio? dio,
    Future<void> Function(String command)? launchDetached,
    // Defaults to the real manifest (or the --dart-define build-time override — see RELEASE.md's
    // "Rolling out safely"). Tests and any other caller that needs a different manifest (e.g. a
    // scratch one) pass this directly instead.
    String? metadataUrl,
    // Defaults to the real Flutter build mode — see checkOnce()'s guard. `flutter test` always runs
    // outside release mode, so tests that want to exercise checkOnce()'s real logic pass `true` here.
    bool? releaseMode,
    // Defaults to the real host OS. Tests force this to exercise the Linux packaging/relaunch branch
    // (tar/version.txt instead of ditto/plutil) from any host, since the actual archive tooling used
    // on that branch (tar) is present on every dev machine, unlike ditto/plutil on Linux.
    bool? isLinux,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 30),
             ),
           ),
       _launchDetached = launchDetached ?? _defaultLaunchDetached,
       _metadataUrlForInstance = metadataUrl ?? _metadataUrl,
       _releaseMode = releaseMode ?? kReleaseMode,
       _isLinux = isLinux ?? Platform.isLinux;

  String get _otaKey => _isLinux ? _otaKeyLinux : _otaKeyMacOS;

  /// Fetches the manifest and returns the newer entry, or null if this app is already current (or
  /// the manifest/network is unavailable — treated the same as "nothing to do", never surfaced as an
  /// error; this runs unattended in the background).
  ///
  /// A debug or profile build never reports an update — self-installing (swapping the running .app
  /// bundle for a downloaded release build and relaunching, see [applyStaged]) makes no sense for a
  /// local dev build and would silently clobber it mid-session.
  Future<UpdateInfo?> checkOnce({String? currentVersion}) async {
    if (!_releaseMode) return null;
    try {
      final running = currentVersion ?? await runningAppVersion();
      final response = await _dio.get<Map<String, dynamic>>(_metadataUrlForInstance);
      final entry = response.data?[_otaKey];
      if (entry is! Map) return null;
      final version = entry['version'];
      final url = entry['url'];
      final sha256 = entry['sha256'];
      final size = entry['size'];
      if (version is! String ||
          url is! String ||
          sha256 is! String ||
          size is! int) {
        return null;
      }
      if (!semverGt(version, running)) return null;
      return UpdateInfo(
        version: version,
        url: url,
        sha256: sha256,
        size: size,
        forced: isForcedUpdate(version, running),
      );
    } catch (error) {
      debugPrint('DesktopUpdater.checkOnce: $error');
      return null;
    }
  }

  /// Checks once immediately, then every [interval] — calls [onUpdateAvailable] each time a newer
  /// build is found (re-finding the same version on a later tick is harmless; the caller is expected
  /// to no-op if it's already showing that version). Cancel the returned [Timer] to stop.
  Timer startChecking({
    Duration interval = const Duration(hours: 6),
    required void Function(UpdateInfo info) onUpdateAvailable,
    // Forwarded to checkOnce() on every tick — tests pass this to avoid checkOnce()'s default
    // runningAppVersion() call, which (via PackageInfo.fromPlatform()) needs a platform method
    // channel real production code gets for free but a plain `test()` doesn't.
    String? currentVersion,
  }) {
    void tick() {
      unawaited(
        checkOnce(currentVersion: currentVersion).then((info) {
          if (info != null) onUpdateAvailable(info);
        }),
      );
    }

    tick();
    return Timer.periodic(interval, (_) => tick());
  }

  /// Downloads [info], verifies its sha256 BEFORE trusting the bytes, unpacks into a fresh temp
  /// directory, and confirms the staged bundle's own Info.plist really carries [info].version.
  /// Returns null (and cleans up anything partially written) on any verification failure.
  Future<StagedUpdate?> downloadAndStage(UpdateInfo info) async {
    Directory? stagingDir;
    try {
      final response = await _dio.get<List<int>>(
        info.url,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes == null || bytes.length != info.size) {
        debugPrint('DesktopUpdater: unexpected download size for ${info.version}');
        return null;
      }
      final hash = await Sha256().hash(bytes);
      final actualSha = hash.bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      if (actualSha != info.sha256) {
        debugPrint(
          'DesktopUpdater: sha256 mismatch for ${info.version} — discarding download',
        );
        return null;
      }

      stagingDir = await Directory.systemTemp.createTemp('harness-update-');
      final archivePath = _isLinux
          ? '${stagingDir.path}/Harness-linux-x64.tar.gz'
          : '${stagingDir.path}/Harness-macos.zip';
      await File(archivePath).writeAsBytes(bytes, flush: true);

      final unpack = _isLinux
          ? await Process.run('/usr/bin/tar', [
              '-xzf',
              archivePath,
              '-C',
              stagingDir.path,
            ])
          : await Process.run('/usr/bin/ditto', [
              '-x',
              '-k',
              archivePath,
              stagingDir.path,
            ]);
      if (unpack.exitCode != 0) {
        debugPrint(
          'DesktopUpdater: ${_isLinux ? 'tar' : 'ditto'} unpack failed: ${unpack.stderr}',
        );
        await stagingDir.delete(recursive: true);
        return null;
      }

      final bundlePath = _isLinux
          ? '${stagingDir.path}/Harness'
          : '${stagingDir.path}/Harness.app';
      if (!Directory(bundlePath).existsSync()) {
        debugPrint('DesktopUpdater: no Harness bundle inside the downloaded archive');
        await stagingDir.delete(recursive: true);
        return null;
      }

      // macOS reads the version Xcode stamped into Info.plist at build time; `flutter build linux`
      // has no equivalent, so the Linux release script (scripts/upload-desktop-linux.sh) writes it
      // into a plain version.txt at the bundle root instead — see lib/core/app_version.dart.
      String? stagedVersion;
      if (_isLinux) {
        final versionFile = File('$bundlePath/version.txt');
        stagedVersion = await versionFile.exists()
            ? (await versionFile.readAsString()).trim()
            : null;
      } else {
        final plutil = await Process.run('/usr/bin/plutil', [
          '-extract',
          'CFBundleShortVersionString',
          'raw',
          '$bundlePath/Contents/Info.plist',
        ]);
        stagedVersion = plutil.exitCode == 0
            ? (plutil.stdout as String?)?.trim()
            : null;
      }
      if (stagedVersion != info.version) {
        debugPrint(
          'DesktopUpdater: staged bundle reports version "$stagedVersion", expected "${info.version}"',
        );
        await stagingDir.delete(recursive: true);
        return null;
      }

      return StagedUpdate(
        version: info.version,
        bundlePath: bundlePath,
        stagingDirPath: stagingDir.path,
      );
    } catch (error) {
      debugPrint('DesktopUpdater.downloadAndStage: $error');
      try {
        await stagingDir?.delete(recursive: true);
      } catch (_) {
        // best-effort cleanup
      }
      return null;
    }
  }

  /// Hands off to a detached helper that waits for THIS process (pid [selfPid]) to exit, backs the
  /// running bundle up as `Harness.app.prev`, swaps [staged] into place, relaunches it, and restores
  /// the backup if the relaunch doesn't stay alive a few seconds later. Returns as soon as the helper
  /// has been spawned — the caller owns actually quitting (e.g. `exit(0)`) right after; this never
  /// exits the app itself, and never touches anything if [runningBundlePath] can't be resolved.
  Future<bool> applyStaged(
    StagedUpdate staged, {
    required int selfPid,
    String? runningBundlePath,
  }) async {
    final bundlePath = runningBundlePath ?? currentBundlePath(null, _isLinux);
    if (bundlePath == null) {
      debugPrint(
        'DesktopUpdater: could not resolve the running bundle path — not applying',
      );
      return false;
    }
    final prevPath = '$bundlePath.prev';
    final executableInBundle = _isLinux
        ? '$bundlePath/harness'
        : '$bundlePath/Contents/MacOS/Harness';
    // macOS relaunches through `open -n` (LaunchServices, so Dock/menu-bar identity stays correct).
    // Linux has no such registry for a plain packaged binary — exec it directly, detached from this
    // shell so it outlives the helper script.
    final relaunch = _isLinux
        ? 'nohup ${_singleQuote(executableInBundle)} >/dev/null 2>&1 & disown'
        : 'open -n ${_singleQuote(bundlePath)}';
    final command = '''
while kill -0 $selfPid 2>/dev/null; do sleep 0.2; done
rm -rf ${_singleQuote(prevPath)}
mv ${_singleQuote(bundlePath)} ${_singleQuote(prevPath)}
mv ${_singleQuote(staged.bundlePath)} ${_singleQuote(bundlePath)}
$relaunch
sleep 3
if pgrep -f ${_singleQuote(executableInBundle)} >/dev/null; then
  rm -rf ${_singleQuote(prevPath)}
else
  rm -rf ${_singleQuote(bundlePath)}
  mv ${_singleQuote(prevPath)} ${_singleQuote(bundlePath)}
  $relaunch
fi
rm -rf ${_singleQuote(staged.stagingDirPath)}
''';
    await _launchDetached(command);
    return true;
  }
}
