/// Data models mirroring the backend/web types.
library;

import '../grid/agent_grid.dart';

enum MachineAuthMode { managed, remote, self, provider }

enum ConnectionStatus { disconnected, connecting, connected, reconnecting }

/// Current SSO identity returned by GET /api/auth/me.
class CurrentUserProfile {
  final String? id;
  final String? name;
  final String email;
  final String? avatarUrl;

  const CurrentUserProfile({
    this.id,
    this.name,
    required this.email,
    this.avatarUrl,
  });

  const CurrentUserProfile.local()
    : id = null,
      name = 'Local session',
      email = 'local terminal',
      avatarUrl = null;

  factory CurrentUserProfile.fromMe(Map<String, dynamic> response) {
    final rawUser = response['user'];
    if (rawUser is! Map) {
      throw const FormatException('missing user profile');
    }
    final user = Map<String, dynamic>.from(rawUser);
    final email = user['email'];
    if (email is! String || email.trim().isEmpty) {
      throw const FormatException('missing user email');
    }
    final rawName = user['name'];
    final rawAvatar = response['avatarUrl'];
    return CurrentUserProfile(
      id: user['id'] is String ? user['id'] as String : null,
      name: rawName is String && rawName.trim().isNotEmpty
          ? rawName.trim()
          : null,
      email: email.trim(),
      avatarUrl: rawAvatar is String && rawAvatar.trim().isNotEmpty
          ? rawAvatar.trim()
          : null,
    );
  }

  String get displayName => name ?? email;

  String get initials {
    final source = (name ?? email).trim();
    if (source.isEmpty) return '?';
    final words = source.split(RegExp(r'\s+')).where((word) => word.isNotEmpty);
    final chars = words.take(2).map((word) => word[0].toUpperCase()).join();
    return chars.isEmpty ? '?' : chars;
  }
}

/// Control-plane machine (GET /api/machines).
class Machine {
  final String machineId;

  /// Legacy fixture-only field. Production `/api/machines` no longer exposes machine API keys.
  final String apiKey;
  final String? computerId;
  final MachineAuthMode authMode;
  final String? engine;
  final String? name;
  final String? hostname;
  final String? status;

  const Machine({
    required this.machineId,
    this.apiKey = '',
    this.computerId,
    required this.authMode,
    this.engine,
    this.name,
    this.hostname,
    this.status,
  });

  String get displayName => (name != null && name!.isNotEmpty)
      ? name!
      : 'machine-${machineId.length > 8 ? machineId.substring(0, 8) : machineId}';

  factory Machine.fromJson(Map<String, dynamic> j) => Machine(
    machineId: j['machineId'] as String,
    apiKey: j['apiKey'] as String? ?? '',
    computerId: j['computerId'] as String?,
    authMode: MachineAuthMode.values.firstWhere(
      (m) => m.name == j['authMode'],
      orElse: () => MachineAuthMode.managed,
    ),
    engine: j['engine'] as String?,
    name: j['name'] as String?,
    hostname: j['hostname'] as String?,
    status: j['status'] as String?,
  );

  Machine copyWith({String? name}) => Machine(
    machineId: machineId,
    apiKey: apiKey,
    computerId: computerId,
    authMode: authMode,
    engine: engine,
    name: name ?? this.name,
    hostname: hostname,
    status: status,
  );
}

/// Data-plane agent (RPC agents_list).
class Agent {
  final String id;
  final String? sessionId;
  final String name;
  final String? engine;
  final String? engineDisplayName;
  final String? engineIconHint;
  final String? parentAgentId;
  final String status;
  final bool terminalAvailable;
  final String? terminalUnavailableReason;

  /// The grid this agent is actually running against, null when it is on the
  /// engine's own login. Read off the live process by the CLI — see [AgentGrid].
  final AgentGrid? grid;

  const Agent({
    required this.id,
    this.sessionId,
    required this.name,
    this.engine,
    this.engineDisplayName,
    this.engineIconHint,
    this.parentAgentId,
    this.status = 'active',
    this.terminalAvailable = false,
    this.terminalUnavailableReason,
    this.grid,
  });

  factory Agent.fromJson(Map<String, dynamic> j) {
    final terminal = j['terminal'];
    final terminalMap = terminal is Map
        ? Map<String, dynamic>.from(terminal)
        : const <String, dynamic>{};
    final runtimes = terminalMap['runtimes'] is List
        ? terminalMap['runtimes'] as List
        : const [];
    final hasTmux = runtimes.any(
      (runtime) => runtime is Map && runtime['backend'] == 'tmux',
    );
    final advertisedAvailable = terminalMap['available'];
    final terminalAvailable = advertisedAvailable is bool
        ? advertisedAvailable
        : hasTmux;
    return Agent(
      id: j['id'] as String,
      sessionId: _safeLabel(j['sessionId']),
      name: j['name'] as String? ?? 'agent',
      engine: _safeEngine(j['engine']),
      engineDisplayName: _safeLabel(j['engineDisplayName']),
      engineIconHint: _safeLabel(j['engineIconHint']),
      parentAgentId: _safeLabel(j['parentAgentId'] ?? j['parentId']),
      status: (j['status'] as String?) ?? 'active',
      terminalAvailable: terminalAvailable,
      terminalUnavailableReason: terminalAvailable
          ? null
          : _safeLabel(terminalMap['reason']) ??
                'terminal unavailable (no verified terminal pane)',
      grid: AgentGrid.fromJson(j['grid']),
    );
  }

  Agent copyWith({String? name}) => Agent(
    id: id,
    sessionId: sessionId,
    name: name ?? this.name,
    engine: engine,
    engineDisplayName: engineDisplayName,
    engineIconHint: engineIconHint,
    parentAgentId: parentAgentId,
    status: status,
    terminalAvailable: terminalAvailable,
    terminalUnavailableReason: terminalUnavailableReason,
    grid: grid,
  );

  static String? _safeEngine(Object? raw) {
    if (raw is! String || raw.isEmpty || raw.length > 64) return null;
    return RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(raw) ? raw : null;
  }

  static String? _safeLabel(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    return raw.length <= 80 ? raw : raw.substring(0, 80);
  }
}
