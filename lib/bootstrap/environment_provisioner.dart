import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';

import '../core/harness_cli_runner.dart';

/// Public, release-managed metadata for the Node runtime that the desktop app
/// owns. It is deliberately separate from the desktop-app updater so new
/// installs can receive a pinned runtime without changing system Node.
const _defaultRuntimeMetadataUrl =
    'https://storage.googleapis.com/s3-autonomous-upgrade-3/harness/runtime/metadata.json';
const _runtimeMetadataUrlOverride = String.fromEnvironment(
  'HARNESS_RUNTIME_METADATA_URL',
);

String get _runtimeMetadataUrl => _runtimeMetadataUrlOverride.isEmpty
    ? _defaultRuntimeMetadataUrl
    : _runtimeMetadataUrlOverride;

enum EnvironmentStep { node, harness, tmux }

enum EnvironmentStepStatus { pending, running, ready, needsTerminal, failed }

class EnvironmentReadiness {
  final Map<EnvironmentStep, EnvironmentStepStatus> steps;
  final String? message;
  final List<String> output;

  const EnvironmentReadiness({
    required this.steps,
    this.message,
    this.output = const [],
  });

  factory EnvironmentReadiness.initial() => EnvironmentReadiness(
    steps: {
      for (final step in EnvironmentStep.values)
        step: EnvironmentStepStatus.pending,
    },
  );

  bool get isReady =>
      steps.values.every((status) => status == EnvironmentStepStatus.ready);

  bool get needsTerminal => steps.values.any(
    (status) => status == EnvironmentStepStatus.needsTerminal,
  );

  EnvironmentReadiness copyWith({
    Map<EnvironmentStep, EnvironmentStepStatus>? steps,
    String? message,
    List<String>? output,
  }) => EnvironmentReadiness(
    steps: steps ?? this.steps,
    message: message,
    output: output ?? this.output,
  );
}

class ManagedNodeArtifact {
  final String version;
  final Uri url;
  final String sha256;
  final int? size;
  final String archiveRoot;

  const ManagedNodeArtifact({
    required this.version,
    required this.url,
    required this.sha256,
    this.size,
    required this.archiveRoot,
  });

  factory ManagedNodeArtifact.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    final url = json['url'];
    final sha256 = json['sha256'];
    final size = json['size'];
    final archiveRoot = json['archiveRoot'];
    if (version is! String ||
        url is! String ||
        sha256 is! String ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256) ||
        size is! int ||
        size <= 0 ||
        archiveRoot is! String ||
        archiveRoot.isEmpty) {
      throw const FormatException('Invalid managed Node runtime metadata');
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') {
      throw const FormatException('Managed Node runtime URL must use HTTPS');
    }
    return ManagedNodeArtifact(
      version: version,
      url: uri,
      sha256: sha256.toLowerCase(),
      size: size,
      archiveRoot: archiveRoot,
    );
  }

  /// Bootstrap fallback while the owned GCS runtime channel is not published
  /// yet. The version and checksums are pinned in the desktop build, not read
  /// from the network, so the archive still has an integrity check.
  factory ManagedNodeArtifact.officialFallback(String platformKey) {
    const version = 'v22.23.2';
    const checksums = {
      'darwin-arm64':
          '61130f394c1630d211dd50aecc4353d379480f36d3ac913cd85dbba1aed585c6',
      'darwin-x64':
          '58e99022c2ff89395576cc7fd4d98cea24bb68081475d5f88b801ee8729fb026',
    };
    final checksum = checksums[platformKey];
    if (checksum == null) {
      throw StateError('No official Node fallback for $platformKey');
    }
    return ManagedNodeArtifact(
      version: version,
      url: Uri.parse(
        'https://nodejs.org/dist/$version/node-$version-$platformKey.tar.gz',
      ),
      sha256: checksum,
      archiveRoot: 'node-$version-$platformKey',
    );
  }
}

typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
});

typedef TerminalLauncher = Future<void> Function(String scriptPath);
typedef ArchitectureReader = Future<String> Function();

Future<ProcessResult> _defaultRun(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
}) => Process.run(executable, arguments, environment: environment);

Future<String> _defaultArchitecture() async {
  final result = await Process.run('/usr/bin/uname', ['-m']);
  if (result.exitCode != 0) {
    throw StateError('Could not determine Mac architecture');
  }
  return (result.stdout as String).trim();
}

Future<void> _defaultOpenTerminal(String scriptPath) =>
    Process.start('/usr/bin/open', ['-a', 'Terminal', scriptPath]).then((_) {});

/// Prepares the only system dependencies required by the desktop transport.
///
/// Node lives beneath [harnessHome] rather than in Homebrew/nvm/PATH. The
/// CLI launcher is written against that exact binary, so launching Harness
/// from Finder and from Terminal has identical runtime behavior.
class EnvironmentProvisioner {
  final Directory harnessHome;
  final Dio _dio;
  final ProcessRunner _run;
  final TerminalLauncher _openTerminal;
  final ArchitectureReader _architecture;
  final bool _isMacOS;

  EnvironmentProvisioner({
    Directory? harnessHome,
    Dio? dio,
    ProcessRunner? run,
    TerminalLauncher? openTerminal,
    ArchitectureReader? architecture,
    bool? isMacOS,
  }) : harnessHome = harnessHome ?? Directory(_defaultHarnessHome()),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(minutes: 2),
             ),
           ),
       _run = run ?? _defaultRun,
       _openTerminal = openTerminal ?? _defaultOpenTerminal,
       _architecture = architecture ?? _defaultArchitecture,
       _isMacOS = isMacOS ?? Platform.isMacOS;

  static String _defaultHarnessHome() {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError('Could not resolve the current user home directory');
    }
    return '$home/.harness';
  }

  Directory get runtimeDirectory => Directory('${harnessHome.path}/runtime');
  File get _currentNodeFile => File('${runtimeDirectory.path}/current-node');

  Future<EnvironmentReadiness> ensureReady({
    required void Function(EnvironmentReadiness value) onProgress,
  }) async {
    var state = EnvironmentReadiness.initial();
    void emit({
      EnvironmentStep? step,
      EnvironmentStepStatus? status,
      String? message,
      String? output,
    }) {
      final next = Map<EnvironmentStep, EnvironmentStepStatus>.from(
        state.steps,
      );
      if (step != null && status != null) next[step] = status;
      final lines = [...state.output];
      if (output != null && output.trim().isNotEmpty) {
        lines.add(output.trim());
        if (lines.length > 12) lines.removeRange(0, lines.length - 12);
      }
      state = EnvironmentReadiness(
        steps: next,
        message: message,
        output: lines,
      );
      onProgress(state);
    }

    if (!_isMacOS) {
      emit(
        step: EnvironmentStep.node,
        status: EnvironmentStepStatus.failed,
        message:
            'Automatic environment setup is currently available on macOS only.',
      );
      return state;
    }

    try {
      emit(
        step: EnvironmentStep.node,
        status: EnvironmentStepStatus.running,
        message: 'Preparing the Harness Node runtime…',
      );
      final node = await _ensureNode();
      emit(
        step: EnvironmentStep.node,
        status: EnvironmentStepStatus.ready,
        output: 'Node ready: ${node.path}',
      );

      emit(
        step: EnvironmentStep.harness,
        status: EnvironmentStepStatus.running,
        message: 'Installing Harness CLI…',
      );
      await _ensureHarness(node);
      emit(
        step: EnvironmentStep.harness,
        status: EnvironmentStepStatus.ready,
        output: 'Harness CLI ready',
      );

      emit(
        step: EnvironmentStep.tmux,
        status: EnvironmentStepStatus.running,
        message: 'Checking tmux…',
      );
      final tmux = await _ensureTmux();
      if (!tmux) {
        emit(
          step: EnvironmentStep.tmux,
          status: EnvironmentStepStatus.needsTerminal,
          message: 'Complete the macOS setup in Terminal, then click Retry.',
          output: 'Terminal opened to install Homebrew and tmux.',
        );
        return state;
      }
      emit(
        step: EnvironmentStep.tmux,
        status: EnvironmentStepStatus.ready,
        message: 'Environment ready.',
        output: 'tmux ready',
      );
      return state;
    } catch (error) {
      final failed = state.steps.entries
          .where((entry) => entry.value == EnvironmentStepStatus.running)
          .map((entry) => entry.key)
          .firstOrNull;
      emit(
        step: failed,
        status: EnvironmentStepStatus.failed,
        message: 'Environment setup failed: $error',
      );
      return state;
    }
  }

  Future<File> _ensureNode() async {
    final existing = await _readHealthyNode();
    if (existing != null) return existing;

    final architecture = await _architecture();
    final platformKey = switch (architecture) {
      'arm64' => 'darwin-arm64',
      'x86_64' => 'darwin-x64',
      _ => throw StateError('Unsupported Mac architecture: $architecture'),
    };
    final artifact = await _nodeArtifactFor(platformKey);
    final response = await _dio.get<List<int>>(
      artifact.url.toString(),
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = response.data;
    if (bytes == null ||
        (artifact.size != null && bytes.length != artifact.size)) {
      throw StateError('Managed Node download size did not match metadata');
    }
    final hash = await Sha256().hash(bytes);
    final actual = hash.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    if (actual != artifact.sha256) {
      throw StateError('Managed Node download failed checksum verification');
    }

    await runtimeDirectory.create(recursive: true);
    await _makePrivate(runtimeDirectory);
    final staging = Directory(
      '${runtimeDirectory.path}/.node-staging-$pid-${DateTime.now().microsecondsSinceEpoch}',
    );
    await staging.create(recursive: true);
    await _makePrivate(staging);
    try {
      final archive = File('${staging.path}/node.tar.gz');
      await archive.writeAsBytes(bytes, flush: true);
      final extract = await _run('/usr/bin/tar', [
        '-xzf',
        archive.path,
        '-C',
        staging.path,
      ]);
      if (extract.exitCode != 0) {
        throw StateError(
          'Could not unpack managed Node: ${_resultText(extract)}',
        );
      }
      final source = Directory('${staging.path}/${artifact.archiveRoot}');
      final sourceNode = File('${source.path}/bin/node');
      if (!await sourceNode.exists()) {
        throw const FormatException('Managed Node archive has no bin/node');
      }
      final target = Directory(
        '${runtimeDirectory.path}/node-${artifact.version}-$platformKey',
      );
      if (!await target.exists()) {
        await source.rename(target.path);
        await _makePrivate(target);
      }
      final node = File('${target.path}/bin/node');
      if (!await _isHealthyNode(node)) {
        throw StateError(
          'Installed Node does not satisfy the Harness requirement',
        );
      }
      await _writeCurrentNode(node);
      return node;
    } finally {
      if (await staging.exists()) {
        await staging.delete(recursive: true);
      }
    }
  }

  Future<ManagedNodeArtifact> _nodeArtifactFor(String platformKey) async {
    try {
      final metadata = await _dio.get<Map<String, dynamic>>(
        _runtimeMetadataUrl,
      );
      final root = metadata.data?['node'];
      if (root is! Map) {
        throw const FormatException('Missing Node runtime metadata');
      }
      final raw = root[platformKey];
      if (raw is! Map) {
        throw StateError('No managed Node runtime for $platformKey');
      }
      return ManagedNodeArtifact.fromJson(Map<String, dynamic>.from(raw));
    } on DioException catch (error) {
      // The release channel is additive. A clean install must not be broken
      // merely because its first runtime manifest has not been uploaded yet.
      if (error.response?.statusCode == HttpStatus.notFound) {
        return ManagedNodeArtifact.officialFallback(platformKey);
      }
      rethrow;
    }
  }

  Future<File?> _readHealthyNode() async {
    try {
      final raw = (await _currentNodeFile.readAsString()).trim();
      if (raw.isEmpty || !raw.startsWith('${runtimeDirectory.path}/')) {
        return null;
      }
      final node = File(raw);
      return await _isHealthyNode(node) ? node : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _isHealthyNode(File node) async {
    if (!await node.exists()) return false;
    final result = await _run(node.path, ['--version']);
    if (result.exitCode != 0) return false;
    final match = RegExp(r'^v?(\d+)\.')
        .firstMatch((result.stdout as String).trim());
    return match != null && int.parse(match.group(1)!) >= 20;
  }

  Future<void> _writeCurrentNode(File node) async {
    final temporary = File('${runtimeDirectory.path}/.current-node-$pid.tmp');
    await temporary.writeAsString('${node.path}\n', flush: true);
    await _makePrivate(temporary);
    await temporary.rename(_currentNodeFile.path);
    await _makePrivate(_currentNodeFile);
  }

  Future<void> _ensureHarness(File node) async {
    final runner = HarnessCliRunner(harnessHome: harnessHome, runProcess: _run);
    ProcessResult? status;
    try {
      status = await runner.run(['auth', 'status', '--json']);
    } on ProcessException {
      // No legacy launcher on a clean install yet; install below.
    }
    if (status != null &&
        status.exitCode == 0 &&
        (status.stdout as String).trim().isNotEmpty) {
      return;
    }
    final install = await _run(
      '/bin/sh',
      [
        '-c',
        // Served by the Harness web application; the retired top-level /install.sh is gone.
        // A stale URL is worse here than anywhere else: a 404 piped into bash still exits 0 (measured),
        // so the `install.exitCode != 0` check below would pass and the failure would only surface as
        // the confusing "CLI did not start after installation" a few lines further down.
        'set -e; curl -fsSL https://harness.autonomous.ai/cli/install.sh | /bin/sh',
      ],
      environment: {...Platform.environment, 'HARNESS_NODE_BINARY': node.path},
    );
    if (install.exitCode != 0) {
      throw StateError('Harness installer failed: ${_resultText(install)}');
    }
    final verified = await runner.run(['auth', 'status', '--json']);
    if (verified.exitCode != 0 || (verified.stdout as String).trim().isEmpty) {
      throw StateError(
        'Harness CLI did not start after installation: ${_resultText(verified)}',
      );
    }
  }

  Future<bool> _ensureTmux() async {
    if (await _hasTmux()) return true;
    final brew = await _shell('command -v brew');
    if (brew.exitCode == 0 && (brew.stdout as String).trim().isNotEmpty) {
      final install = await _shell('brew install tmux');
      if (install.exitCode != 0) {
        throw StateError('Could not install tmux: ${_resultText(install)}');
      }
      return _hasTmux();
    }
    final script = await _writeTerminalBootstrapScript();
    await _openTerminal(script.path);
    return false;
  }

  Future<bool> _hasTmux() async {
    final result = await _shell('command -v tmux >/dev/null && tmux -V');
    return result.exitCode == 0;
  }

  Future<File> _writeTerminalBootstrapScript() async {
    final directory = await Directory.systemTemp.createTemp('harness-tmux-');
    final script = File('${directory.path}/install-tmux.command');
    await script.writeAsString('''#!/bin/zsh
set -e
if ! xcode-select -p >/dev/null 2>&1; then
  echo 'Installing Apple Command Line Tools. Finish the macOS dialog, then return to Harness and click Retry.'
  xcode-select --install || true
  exit 0
fi
if ! command -v brew >/dev/null 2>&1; then
  echo 'Installing Homebrew (macOS may ask for your password)…'
  /bin/bash -c "\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "\$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
brew install tmux
echo 'tmux is ready. Return to Harness.'
''', flush: true);
    await _run('/bin/chmod', ['700', script.path]);
    return script;
  }

  Future<ProcessResult> _shell(
    String command, {
    Map<String, String>? environment,
  }) => _run('/bin/zsh', [
    '-l',
    '-c',
    'export PATH="\$HOME/.local/bin:\$PATH"; $command',
  ], environment: environment);

  Future<void> _makePrivate(FileSystemEntity entity) async {
    final result = await _run('/bin/chmod', ['700', entity.path]);
    if (result.exitCode != 0) {
      throw StateError(
        'Could not secure ${entity.path}: ${_resultText(result)}',
      );
    }
  }

  String _resultText(ProcessResult result) {
    final text = '${result.stderr}\n${result.stdout}'.trim();
    return text.length <= 700 ? text : text.substring(text.length - 700);
  }
}

extension on Iterable<EnvironmentStep> {
  EnvironmentStep? get firstOrNull => isEmpty ? null : first;
}
