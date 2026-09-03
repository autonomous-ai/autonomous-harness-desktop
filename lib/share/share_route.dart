import 'backend_detector.dart';

/// The three ways this computer can put intelligence on a grid.
///
/// One axis, three values, and every state of the page is one of them plus
/// "already sharing". Ported from Grid, where they used to be three stacked
/// disclosures: rows you opened one at a time, each unfolding a form under the
/// two you had not read. As a route picked on the left and configured on the
/// right, all three stay visible while one is being set up.
enum ShareRoute { local, key, server }

/// Which route the page opens on, given what this machine can actually do.
///
/// Never a route the machine cannot take: opening on "run a model here" for a
/// computer with no engine puts a form in front of someone whose first move has
/// to be somewhere else. Local leads when it is possible because it is the only
/// route that costs nothing and sends nothing — an answer the other two cannot
/// give.
ShareRoute defaultShareRoute({
  required bool canRunLocal,
  required bool serverFound,
  required bool hasKeyProvider,
}) {
  if (canRunLocal) return ShareRoute.local;
  // Something is already running here — one press from shared, no download.
  if (serverFound) return ShareRoute.server;
  if (hasKeyProvider) return ShareRoute.key;
  // The endpoint form takes a typed address, so it is the one route that is
  // possible even when nothing was detected.
  return ShareRoute.server;
}

/// One route as the rail draws it: what it is called, and one line describing
/// it in terms of what was actually found on this machine.
///
/// A view model rather than three literals in a `build`, because every line
/// changes with what the machine has — an engine that still needs installing,
/// whether Ollama is running or merely present. Those are the sentences that go
/// stale silently, so they are built in one tested place.
class ShareRouteOffer {
  const ShareRouteOffer({
    required this.route,
    required this.title,
    required this.line,
    this.detected = 0,
  });

  final ShareRoute route;
  final String title;
  final String line;

  /// Engines found here for this route — only the server route ever finds any.
  /// The count, not a rendering of it: the rail spends it on which line to
  /// write, the detail pane on how to open its paragraph.
  final int detected;
}

/// The routes this machine can take, in the order the rail shows them.
///
/// A route the machine cannot take is left out rather than drawn disabled: a
/// greyed row still has to be read, and "you can't do this" is not something a
/// first-time reader can act on.
List<ShareRouteOffer> buildShareRouteOffers({
  required bool canRunLocal,
  required bool needsModel,
  required List<String> keyProviders,
  required List<DetectedBackend> backends,
}) {
  final external = [
    for (final backend in backends)
      if (backend.isExternal) backend,
  ];
  final running = [
    for (final backend in external)
      if (backend.running) backend,
  ];
  return [
    if (canRunLocal)
      ShareRouteOffer(
        route: ShareRoute.local,
        title: 'Run a local model',
        line: needsModel
            ? 'Downloads a model first, then runs it on your own hardware.'
            : 'Your own hardware does the work. Weights and prompts never '
                  'leave the machine.',
      ),
    if (keyProviders.isNotEmpty)
      ShareRouteOffer(
        route: ShareRoute.key,
        title: 'Share frontier models via your API key',
        // The provider is named from what the installed CLI whitelists, never a
        // hopeful list: "your OpenAI key" on a build that serves someone else's
        // points at a provider this machine cannot reach.
        line:
            'Nothing to download. Bring your own ${_and(keyProviders)} key, '
            'and pay for what the grid uses.',
      ),
    ShareRouteOffer(
      route: ShareRoute.server,
      // The verb is about the route, not the moment: on the common machine the
      // engine is installed and stopped, which is exactly what this starts. The
      // line under it carries the state, so a server already running is never
      // told to start again.
      title: 'Start an engine you already have',
      detected: external.length,
      line: switch ((running.firstOrNull, external.firstOrNull)) {
        (final live?, _) =>
          '${live.label} is running here. Point Grid at it and share it '
              'exactly as it is.',
        (_, final found?) =>
          '${found.label} is installed here. Start it and share it as it is.',
        _ => 'Point Grid at any OpenAI-compatible engine on this computer.',
      },
    ),
  ];
}

/// `OpenAI`, `OpenAI or Anthropic`, `OpenAI, Anthropic or Gemini`.
String _and(List<String> names) {
  if (names.length <= 1) return names.firstOrNull ?? '';
  final head = names.sublist(0, names.length - 1).join(', ');
  return '$head or ${names.last}';
}
