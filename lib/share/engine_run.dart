import 'dart:convert';
import 'dart:io';

import 'grid_paths.dart';

/// How an engine in this machine's union serves.
enum EngineKind {
  /// The built-in llama.cpp engine serving a local GGUF.
  local,

  /// An OpenAI-compatible server on this machine the engine points at.
  external,

  /// A hosted provider served through the vendor on the user's own key.
  api,
}

/// One engine inside this machine's per-grid union.
///
/// A machine has a single identity per grid but serves the union of every
/// `grid join` it ran, so a record holds one of these per joined engine — which
/// is what lets the page list them and stop one at a time.
class EngineSpec {
  const EngineSpec({required this.models, this.apiKind, this.endpointUrl});

  final List<String> models;
  final String? apiKind;
  final String? endpointUrl;

  EngineKind get kind {
    if (apiKind != null && apiKind!.isNotEmpty) return EngineKind.api;
    if (endpointUrl != null && endpointUrl!.isNotEmpty) {
      return EngineKind.external;
    }
    return EngineKind.local;
  }

  /// What `grid leave --engine <selector>` matches to drop just this one: the
  /// endpoint URL when external, else its first served model. Null when the
  /// spec carries nothing to match on, and the row then offers stop-all only.
  String? get leaveSelector {
    if (endpointUrl != null && endpointUrl!.isNotEmpty) return endpointUrl;
    return models.isEmpty ? null : models.first;
  }

  factory EngineSpec.fromJson(Map<String, dynamic> json) => EngineSpec(
    models: _stringList(json['models']),
    apiKind: json['api_kind'] is String ? json['api_kind'] as String : null,
    endpointUrl: json['endpoint_url'] is String
        ? json['endpoint_url'] as String
        : null,
  );
}

/// One engine's run record, written by the CLI when `grid join` launches a
/// detached engine: `~/.grid/run/engines/<grid_id>/<engine_id>.json`.
///
/// This is the only reason the app knows anything after a restart. The engine
/// outlives us — that is the point of it — so "is this computer sharing?" can
/// only be answered by what the CLI left on disk, never by what we remember.
class EngineRunRecord {
  const EngineRunRecord({
    required this.engineId,
    required this.gridId,
    required this.models,
    required this.pid,
    this.engines = const [],
    this.endpointPort,
  });

  final String engineId;
  final String gridId;

  /// The flat union of every advertised model this machine serves here.
  final List<String> models;

  /// The detached engine's process id, so liveness is a question about a real
  /// process rather than about a file that was written once.
  final int? pid;

  final List<EngineSpec> engines;

  /// The local engine's own OpenAI port, when one is serving.
  final int? endpointPort;

  factory EngineRunRecord.fromJson(Map<String, dynamic> json) {
    final models = _stringList(json['models']);
    final raw = json['engines'];
    // A record written before `engines[]` existed still describes one engine —
    // synthesised from the flat fields rather than dropped, which would read as
    // a machine that had stopped sharing.
    final engines = raw is List && raw.isNotEmpty
        ? [
            for (final entry in raw)
              if (entry is Map)
                EngineSpec.fromJson(Map<String, dynamic>.from(entry)),
          ]
        : [
            EngineSpec(
              models: models,
              apiKind: json['api_kind'] is String
                  ? json['api_kind'] as String
                  : null,
              endpointUrl: json['endpoint_url'] is String
                  ? json['endpoint_url'] as String
                  : null,
            ),
          ];
    return EngineRunRecord(
      engineId: '${json['engine_id'] ?? ''}',
      gridId: '${json['grid_id'] ?? ''}',
      models: models,
      pid: json['pid'] is int ? json['pid'] as int : null,
      engines: engines,
      endpointPort: json['endpoint_port'] is int
          ? json['endpoint_port'] as int
          : null,
    );
  }
}

/// Every run record for [gridId].
///
/// The directory is scanned rather than a filename guessed, because the engine
/// id in the name is the CLI's own and not the `--name` we passed — it keeps
/// ours only as a display name, so guessing misses the live record entirely.
/// Lenient throughout: a missing directory or one unreadable file is skipped,
/// never thrown, so a bad record cannot take the page down with it.
List<EngineRunRecord> readEngineRuns(String gridId, {Directory? runDir}) {
  final dir = runDir ?? GridPaths.engineRunDir(gridId);
  if (!dir.existsSync()) return const [];
  final out = <EngineRunRecord>[];
  for (final entity in dir.listSync()) {
    if (entity is! File || !entity.path.endsWith('.json')) continue;
    try {
      final decoded = jsonDecode(entity.readAsStringSync());
      if (decoded is Map) {
        out.add(EngineRunRecord.fromJson(Map<String, dynamic>.from(decoded)));
      }
    } on Object {
      continue;
    }
  }
  return out;
}

/// True when [pid] names a live process.
///
/// POSIX `kill -0` asks whether a process exists without signalling it — the
/// only way to ask, since Dart has no signal 0. An absolute path because a
/// packaged app's PATH is Finder's, not a shell's.
///
/// Where the question cannot be asked at all — Windows, or a `kill` that is not
/// there — the answer is **yes**, and that direction is deliberate: every stop
/// path runs `grid leave` regardless, so believing a dead engine is alive costs
/// one harmless command, while believing a live one is dead invites a second
/// join on top of the first.
bool pidIsAlive(int? pid) {
  // Null means a record we cannot check, which is the unverifiable case above
  // rather than a dead one. This is a deliberate difference from the Grid app,
  // which reads null as dead.
  if (pid == null) return true;
  if (Platform.isWindows) return true;
  try {
    return Process.runSync('/bin/kill', ['-0', '$pid']).exitCode == 0;
  } on ProcessException {
    return true;
  }
}

/// The record whose process is still alive, or null when none is.
///
/// A record on disk is not a running engine: the CLI writes one at join and
/// removes it at leave, so a machine that lost power keeps a record for an
/// engine that died with it. A grid's directory can hold several, stale beside
/// live, which is why this picks by liveness rather than taking the first.
EngineRunRecord? firstLiveRun(
  List<EngineRunRecord> records, {
  bool Function(int? pid)? isAlive,
}) {
  final alive = isAlive ?? pidIsAlive;
  for (final record in records) {
    if (alive(record.pid)) return record;
  }
  return null;
}

List<String> _stringList(Object? value) =>
    value is List ? [for (final entry in value) '$entry'] : const [];
