import 'dart:convert';
import 'dart:io';

import 'grid_paths.dart';

enum BackendKind { ollama, lmStudio, llamaCpp }

/// An inference server found on this computer that a grid could be pointed at.
class DetectedBackend {
  const DetectedBackend({
    required this.kind,
    required this.label,
    required this.baseUrl,
    this.models = const [],
    this.running = true,
  });

  final BackendKind kind;
  final String label;

  /// The OpenAI-compatible base URL to pass to `grid join --at`. Empty for the
  /// CLI's own llama.cpp, which has no server until a join starts one.
  final String baseUrl;
  final List<String> models;

  /// Whether it is actually answering. False for one that is installed but
  /// stopped — the page then offers to start it rather than a serve form.
  final bool running;

  bool get isExternal => baseUrl.isNotEmpty;
}

/// Looks for the engines already on this computer.
///
/// Ported from Grid's own detector, and injectable for the same reason: the
/// three questions it asks — is a server answering, is a file there, is a
/// binary on PATH — are all about the machine it runs on, and a test that had
/// to answer them for real would pass or fail on what the developer happened
/// to have installed.
class BackendDetector {
  BackendDetector({
    Future<List<String>?> Function(String baseUrl)? probeModels,
    bool Function(String path)? fileExists,
    bool Function(String name)? hasExecutable,
  }) : _probeModels = probeModels ?? _httpProbeModels,
       _fileExists = fileExists ?? _defaultFileExists,
       _hasExecutable = hasExecutable ?? _defaultHasExecutable;

  final Future<List<String>?> Function(String baseUrl) _probeModels;
  final bool Function(String path) _fileExists;
  final bool Function(String name) _hasExecutable;

  static const ollamaBase = 'http://localhost:11434/v1';
  static const lmStudioBase = 'http://localhost:1234/v1';

  Future<List<DetectedBackend>> detect() async {
    final found = <DetectedBackend>[];

    final ollama = await _probeModels(ollamaBase);
    if (ollama != null) {
      found.add(
        DetectedBackend(
          kind: BackendKind.ollama,
          label: 'Ollama',
          baseUrl: ollamaBase,
          models: ollama,
        ),
      );
    } else if (_hasExecutable('ollama')) {
      found.add(
        const DetectedBackend(
          kind: BackendKind.ollama,
          label: 'Ollama',
          baseUrl: ollamaBase,
          running: false,
        ),
      );
    }

    final lmStudio = await _probeModels(lmStudioBase);
    if (lmStudio != null) {
      found.add(
        DetectedBackend(
          kind: BackendKind.lmStudio,
          label: 'LM Studio',
          baseUrl: lmStudioBase,
          models: lmStudio,
        ),
      );
    }

    if (_fileExists(GridPaths.llamaServerBin.path)) {
      found.add(
        const DetectedBackend(
          kind: BackendKind.llamaCpp,
          label: 'llama.cpp (grid)',
          baseUrl: '',
        ),
      );
    }

    return found;
  }

  /// Is an OpenAI-compatible server answering at [baseUrl]? Used to poll for
  /// one coming up after we started it.
  static Future<bool> isServerUp(String baseUrl) async =>
      (await _httpProbeModels(baseUrl)) != null;

  /// GET `<baseUrl>/models` and return the ids, or null when unreachable.
  /// Short timeouts throughout: this runs while a page is opening, and a
  /// backend that is not there must not be worth waiting for.
  static Future<List<String>?> _httpProbeModels(String baseUrl) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    try {
      final request = await client
          .getUrl(Uri.parse('$baseUrl/models'))
          .timeout(const Duration(seconds: 2));
      final response = await request.close().timeout(
        const Duration(seconds: 2),
      );
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(await response.transform(utf8.decoder).join());
      if (decoded is! Map || decoded['data'] is! List) return const [];
      return [
        for (final row in decoded['data'] as List)
          if (row is Map) '${row['id']}',
      ];
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static bool _defaultFileExists(String path) => File(path).existsSync();

  /// On PATH, or — on macOS — shipped inside `/Applications/<Name>.app`, which
  /// is how most people have Ollama without its CLI ever being on PATH.
  static bool _defaultHasExecutable(String name) {
    final home = Platform.environment['HOME'];
    final dirs = [
      if (home != null && home.isNotEmpty) '$home/.local/bin',
      '/opt/homebrew/bin',
      '/usr/local/bin',
      ...(Platform.environment['PATH'] ?? '').split(':'),
    ];
    for (final dir in dirs) {
      if (dir.isNotEmpty && File('$dir/$name').existsSync()) return true;
    }
    if (Platform.isMacOS) {
      final app = '${name[0].toUpperCase()}${name.substring(1)}';
      return Directory('/Applications/$app.app').existsSync();
    }
    return false;
  }
}
