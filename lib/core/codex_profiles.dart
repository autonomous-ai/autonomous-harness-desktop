import 'dart:convert';
import 'dart:io';

import 'harness_file_store.dart';
import 'local_key_value_store.dart';
import 'test_run.dart';

/// A reference to an existing Codex state folder. No credentials are copied.
class LocalCodexProfile {
  const LocalCodexProfile(this.path);

  final String path;
  String get label => path.split(Platform.pathSeparator).last;
}

class LocalCodexProfiles {
  LocalCodexProfiles({this.home, LocalKeyValueStore? storage})
    : _storage = storage ?? HarnessFileStore.shared;

  static const _key = 'local_codex_profile_paths';
  final Directory? home;
  final LocalKeyValueStore _storage;

  /// Discover conventional homes and explicitly linked folders. Stat only:
  /// auth.json, config.toml and their contents remain owned by Codex.
  Future<List<LocalCodexProfile>> load() async {
    if (kUnderTest && home == null) return const [];
    final paths = <String>{};
    try {
      final raw = await _storage.read(_key);
      final saved = raw == null ? null : jsonDecode(raw);
      if (saved is List) paths.addAll(saved.whereType<String>());
    } catch (_) {
      // Discovery still works when the optional saved list is unavailable.
    }
    final root = home ?? Directory(Platform.environment['HOME'] ?? '');
    if (root.path.isNotEmpty) {
      try {
        await for (final entry in root.list(followLinks: false)) {
          final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
          if (name == '.codex' || name.startsWith('.codex-')) {
            if (await File('${entry.path}/auth.json').exists() ||
                await File('${entry.path}/config.toml').exists()) {
              paths.add(entry.path);
            }
          }
        }
      } on FileSystemException {
        // Explicitly linked folders can still be available.
      }
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
    return profiles.values.toList()..sort((a, b) => a.label.compareTo(b.label));
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
    return LocalCodexProfile(await directory.resolveSymbolicLinks());
  }

  Future<LocalCodexProfile> link(String path) async {
    final profile = await resolve(path);
    final profiles = await load();
    await _storage.write(
      _key,
      jsonEncode(
        {for (final entry in profiles) entry.path, profile.path}.toList(),
      ),
    );
    return profile;
  }
}
