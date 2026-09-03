import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/serial_port_lease.dart';
import '../core/config.dart';
import '../core/harness_cli_runner.dart';
import '../core/harness_file_store.dart';

const localWsProtocolVersion = 1;
const localTerminalProtocolVersion = 3;

class LocalCliEndpoint {
  final String computerId;
  final Uri wsUri;
  final int protocolVersion;
  final int terminalProtocolVersion;

  const LocalCliEndpoint({
    required this.computerId,
    required this.wsUri,
    required this.protocolVersion,
    required this.terminalProtocolVersion,
  });
}

/// Reads the stable identity shared by the Harness CLI and backend machine record.
class LocalMachineIdentity {
  final File computerIdFile;
  final Map<String, String> environment;

  LocalMachineIdentity({File? computerIdFile, Map<String, String>? environment})
    : environment = environment ?? Platform.environment,
      computerIdFile =
          computerIdFile ??
          File(defaultComputerIdPath(environment: environment));

  static String defaultComputerIdPath({Map<String, String>? environment}) {
    final desktopDirectory = HarnessFileStore.defaultDirectoryPath(
      environment: environment,
    );
    final harnessHome = Directory(desktopDirectory).parent.path;
    return _joinPath(harnessHome, 'computer-id');
  }

  Future<String?> computerId() async {
    final pinned = _normalizeComputerId(environment['ADAPTER_COMPUTER_ID']);
    if (pinned != null) return pinned;
    try {
      final id = (await computerIdFile.readAsString()).trim();
      return _normalizeComputerId(id);
    } catch (_) {
      return null;
    }
  }
}

String _joinPath(String parent, String child) =>
    '$parent${Platform.pathSeparator}$child';

/// Discovers only the CLI bound to the fixed loopback address. The response
/// advertises capabilities but never contains the machine API key.
/// Starts the owned CLI directly. Finder does not need a shell/PATH in order
/// to locate the managed Node runtime and CLI bundle.
Future<void> _defaultSpawnCommand() async {
  await HarnessCliRunner().run(['start']);
}

class LocalCliDiscovery {
  final AppConfig config;
  final Dio _dio;
  final LocalMachineIdentity identity;
  final Future<void> Function() _spawnCommand;

  LocalCliDiscovery({
    required this.config,
    Dio? dio,
    LocalMachineIdentity? identity,
    Future<void> Function()? spawnCommand,
  }) : identity = identity ?? LocalMachineIdentity(),
       _spawnCommand = spawnCommand ?? _defaultSpawnCommand,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(milliseconds: 400),
               receiveTimeout: const Duration(milliseconds: 400),
               sendTimeout: const Duration(milliseconds: 400),
             ),
           );

  Future<String?> computerId() => identity.computerId();

  /// Makes sure the local `harness` daemon is up and answering `/api/status`, spawning `harness
  /// start` if a first probe finds nothing there — every local REST/WS call needs this daemon
  /// running, and unlike `harness login` it does not start on its own. Returns null if the daemon
  /// never comes up within [timeout] (e.g. the CLI is not installed, or `harness login` was never
  /// run), which the caller surfaces as a dedicated "local Harness daemon did not start" failure
  /// rather than a generic connectivity error.
  Future<LocalCliEndpoint?> ensureRunning({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final immediate = await discover();
    if (immediate != null) return immediate;
    // Same reason as the supervisor: while the dial is being flashed the daemon is down on purpose
    // and its port belongs to esptool. Null is the honest answer here — it really is not running.
    if (SerialPortLease.held || SerialPortLease.heldByAnotherProcess()) {
      return null;
    }
    try {
      await _spawnCommand();
    } catch (_) {
      return null;
    }
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 500));
      final endpoint = await discover();
      if (endpoint != null) return endpoint;
    }
    return null;
  }

  /// Keeps the local daemon alive for as long as the returned [Timer] runs: polls [discover] every
  /// [checkInterval] and, whenever it comes back empty, spawns `harness start` and gives it a short
  /// grace window to bind its port before concluding the attempt failed. Failed spawn attempts back
  /// off exponentially (capped) so a persistently broken environment doesn't spin — the poll itself
  /// keeps going at [checkInterval] regardless, since backoff only gates the next SPAWN, not the next
  /// probe. Never surfaces ORDINARY failures to the caller (no exceptions, no
  /// [AppNotifier]-visible error); [onSignedOut] is the single exception, for the one state no
  /// amount of respawning can recover from —
  /// this runs unattended in the background for the app's whole lifetime; callers that need a
  /// one-shot "start now and tell me if it worked" should use [ensureRunning] instead. Cancel the
  /// timer to stop supervising — this never touches the daemon process itself (it self-daemonizes and
  /// must keep running after the app quits, see `harness_daemon_keep_alive` plan).
  Timer startSupervising({
    Duration checkInterval = const Duration(seconds: 5),
    Duration graceStep = const Duration(milliseconds: 500),
    Duration graceWindow = const Duration(seconds: 5),
    Duration initialBackoff = const Duration(seconds: 2),
    Duration maxBackoff = const Duration(seconds: 30),
    Future<bool> Function()? stillSignedIn,
    void Function()? onSignedOut,
  }) {
    var backoff = initialBackoff;
    var nextSpawnAllowedAt = DateTime.now();
    // A spawn+grace-window cycle can outlast `checkInterval` — without this, an overlapping tick
    // would race a second `harness start` before the first cycle's backoff state even lands (the same
    // "port already in use" failure mode a second concurrent spawn hits today).
    var cycleInFlight = false;

    void failedSpawn() {
      nextSpawnAllowedAt = DateTime.now().add(backoff);
      backoff = (backoff * 2) > maxBackoff ? maxBackoff : backoff * 2;
    }

    late final Timer timer;
    timer = Timer.periodic(checkInterval, (_) {
      if (cycleInFlight) return;
      cycleInFlight = true;
      unawaited(() async {
        try {
          // The daemon is DELIBERATELY down while the dial is being flashed — it was stopped so the
          // port could be handed over. Starting it here takes the port back mid-write and kills the
          // flash, which is what made a firmware update fail at a few tens of kilobytes.
          if (SerialPortLease.held || SerialPortLease.heldByAnotherProcess()) {
            return;
          }
          if (await discover() != null) {
            backoff = initialBackoff;
            return;
          }
          if (DateTime.now().isBefore(nextSpawnAllowedAt)) return;
          // A daemon that signed itself OUT — its machine was deleted from another machine, or its
          // session expired — deletes its session file and exits. Respawning it is the one failure
          // this loop cannot fix: every replacement starts without a session and exits again,
          // forever, silently. Stop instead, and let the caller send the user somewhere that helps.
          //
          // Asked here and not on every tick because it costs a `harness auth status` process, and
          // the respawn point is already rate-limited by the backoff above — so this runs once per
          // spawn attempt rather than once every [checkInterval].
          if (stillSignedIn != null && !await stillSignedIn()) {
            timer.cancel();
            onSignedOut?.call();
            return;
          }
          try {
            await _spawnCommand();
          } catch (error) {
            debugPrint(
              'LocalCliDiscovery.startSupervising: spawn failed: $error',
            );
            failedSpawn();
            return;
          }
          final deadline = DateTime.now().add(graceWindow);
          while (DateTime.now().isBefore(deadline)) {
            await Future.delayed(graceStep);
            if (await discover() != null) {
              backoff = initialBackoff;
              return;
            }
          }
          failedSpawn();
        } finally {
          cycleInFlight = false;
        }
      }());
    });
    return timer;
  }

  Future<LocalCliEndpoint?> discover({String? expectedComputerId}) async {
    try {
      final localComputerId = await computerId();
      if (localComputerId == null ||
          (expectedComputerId != null &&
              expectedComputerId != localComputerId)) {
        return null;
      }
      final base = Uri.parse(config.localCliBaseUrl);
      if (base.host != '127.0.0.1' && base.host != 'localhost') return null;
      final response = await _dio.getUri<Map<String, dynamic>>(
        base.resolve('/api/status'),
      );
      final body = response.data;
      // New CLIs expose the initial terminal scan explicitly. A missing field means an older CLI and
      // remains accepted for backward compatibility; false means the daemon is alive but not ready to
      // publish an authoritative empty/non-empty agent list yet.
      if (body?['discoveryReady'] == false) return null;
      final advertisedComputerId = _normalizeComputerId(body?['computerId']);
      final advertised = body?['localWs'];
      if (advertisedComputerId != localComputerId || advertised is! Map) {
        return null;
      }
      final localWs = Map<String, dynamic>.from(advertised);
      final path = localWs['path'];
      final protocolVersion = localWs['protocolVersion'];
      final terminalProtocolVersion = localWs['terminalProtocolVersion'];
      if (path is! String ||
          !path.startsWith('/') ||
          protocolVersion != localWsProtocolVersion ||
          terminalProtocolVersion != localTerminalProtocolVersion ||
          localWs['e2ee'] != false) {
        return null;
      }
      return LocalCliEndpoint(
        computerId: localComputerId,
        wsUri: base
            .resolve(path)
            .replace(scheme: base.scheme == 'https' ? 'wss' : 'ws'),
        protocolVersion: protocolVersion as int,
        terminalProtocolVersion: terminalProtocolVersion as int,
      );
    } catch (_) {
      return null;
    }
  }
}

String? _normalizeComputerId(Object? raw) {
  if (raw is! String) return null;
  final value = raw.trim().toLowerCase().replaceAll('-', '');
  return RegExp(r'^[a-f0-9]{16,64}$').hasMatch(value) ? value : null;
}
