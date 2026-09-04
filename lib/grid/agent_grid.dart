/// Where a running agent's inference actually goes.
///
/// The harness CLI reads this off the live engine process on every discovery pass
/// (`autonomous-harness/cli/src/lib/gridAssignment.ts`) rather than from any record it keeps — a
/// process's environment is fixed at launch and is the only thing that decides where its requests go,
/// so it is also the only honest place to ask.
///
/// It carries no credential. The endpoint and the model are things the app chose in the first place.
class AgentGrid {
  const AgentGrid({required this.baseUrl, this.model});

  /// The relay root the engine was handed. The grid's id is a path segment inside it.
  final String baseUrl;

  /// The model the launch pinned, or null when it left the choice to the engine.
  final String? model;

  static AgentGrid? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final baseUrl = raw['baseUrl'];
    if (baseUrl is! String || baseUrl.isEmpty) return null;
    final model = raw['model'];
    return AgentGrid(
      baseUrl: baseUrl,
      model: model is String && model.isNotEmpty ? model : null,
    );
  }

  /// Value equality, because this is compared rather than held.
  ///
  /// Two parses of the same answer describe the same assignment and must say so: the background
  /// agent poll decides whether a refreshed list differs from the one on screen, and under identity
  /// equality every tick would look like a change. The absence of this was the other half of a bug
  /// where a grid change made outside this app never reached the UI — see `AppNotifier.agentsEqual`.
  @override
  bool operator ==(Object other) =>
      other is AgentGrid && other.baseUrl == baseUrl && other.model == model;

  @override
  int get hashCode => Object.hash(baseUrl, model);
}
