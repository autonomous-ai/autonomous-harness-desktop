import 'dart:convert';
import 'dart:io';

import 'codex_profile_discovery.dart';
import 'harness_file_store.dart';
import 'local_key_value_store.dart';
import 'test_run.dart';

/// A reference to an existing Codex state folder. No credentials are copied.
class LocalCodexProfile {
  const LocalCodexProfile(this.path);

  final String path;
  String get label =>
      path
          .split(Platform.pathSeparator)
          .where((p) => p.isNotEmpty)
          .lastOrNull ??
      path;
}

class LocalCodexProfiles {
  LocalCodexProfiles({
    this.home,
    LocalKeyValueStore? storage,
    Map<String, String>? environment,
  }) : _storage = storage ?? HarnessFileStore.shared,
       environment =
           environment ?? (home == null ? Platform.environment : const {});

  static const _key = 'local_codex_profile_paths';
  final Directory? home;
  final Map<String, String> environment;
  final LocalKeyValueStore _storage;

  /// The caller supplies only Codex homes observed on this computer. Remote
  /// paths must never be interpreted in this computer's filesystem.
  Future<List<LocalCodexProfile>> load({
    Set<String> observedPaths = const {},
  }) async {
    if (kUnderTest && home == null) return const [];
    final paths = {...await _linkedPaths(), ...observedPaths};
    final root =
        home?.path ?? environment['HOME'] ?? environment['USERPROFILE'];
    if (root != null && root.isNotEmpty) {
      paths.addAll(
        await CodexProfileDiscovery(
          home: root,
          environment: environment,
        ).discover(),
      );
    }
    final profiles = <String, LocalCodexProfile>{};
    for (final path in paths) {
      try {
        final profile = await resolve(path);
        profiles[profile.path] = profile;
      } on FileSystemException {
        // A removed folder must not be offered as a working profile.
      } on FormatException {
        // Ignore malformed persisted preferences.
      }
    }
    return profiles.values.toList()..sort((a, b) {
      final byName = a.label.toLowerCase().compareTo(b.label.toLowerCase());
      return byName == 0 ? a.path.compareTo(b.path) : byName;
    });
  }

  Future<Set<String>> _linkedPaths() async {
    try {
      final raw = await _storage.read(_key);
      final saved = raw == null ? null : jsonDecode(raw);
      if (saved is List) return saved.whereType<String>().take(256).toSet();
    } catch (_) {
      // Discovery still works when the optional saved list is unavailable.
    }
    return {};
  }

  Future<LocalCodexProfile> resolve(String path) async {
    if (!path.startsWith(Platform.pathSeparator) ||
        path.length > 4096 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(path)) {
      throw const FormatException('Choose an absolute Codex profile folder.');
    }
    final directory = Directory(path);
    if (!await directory.exists()) {
      throw const FileSystemException(
        'The Codex profile folder is unavailable.',
      );
    }
    final resolved = await directory.resolveSymbolicLinks();
    if (resolved.length > 4096 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(resolved)) {
      throw const FormatException('Choose an absolute Codex profile folder.');
    }
    return LocalCodexProfile(resolved);
  }

  Future<LocalCodexProfile> link(String path) async {
    final profile = await resolve(path);
    final linked = await _linkedPaths();
    await _storage.write(_key, jsonEncode({...linked, profile.path}.toList()));
    return profile;
  }
}
