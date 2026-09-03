import 'dart:io';

import 'api_providers.dart';
import 'backend_detector.dart';
import 'context_length.dart';
import 'grid_cli.dart';
import 'grid_paths.dart';
import 'local_models.dart';
import 'share_route.dart';

/// What this computer can actually do, in one answer.
///
/// Everything the page decides — which routes to offer, which one to open on,
/// whether a route can be started — is a question about this machine, and they
/// are asked together so the page never draws half of one machine and half of
/// another. A field here is a fact that was checked, never a hope.
class ShareCapabilities {
  const ShareCapabilities({
    required this.cliInstalled,
    required this.engineInstalled,
    required this.models,
    required this.backends,
    required this.keyProviders,
  });

  /// Nothing on this page is possible without it, and this app does not install
  /// it — so this is the one state the page has to be able to explain.
  final bool cliInstalled;

  /// The CLI's llama.cpp is on disk, so a local model can be served.
  final bool engineInstalled;

  final List<LocalModel> models;
  final List<DetectedBackend> backends;
  final List<KeyProviderOffer> keyProviders;

  static const empty = ShareCapabilities(
    cliInstalled: false,
    engineInstalled: false,
    models: [],
    backends: [],
    keyProviders: [],
  );

  /// The local route is offered when the engine is here, with or without a
  /// model: a computer with the engine and no weights has one download in front
  /// of it, which is a step on the route rather than a reason to hide it.
  bool get canRunLocal => cliInstalled && engineInstalled;

  bool get needsModel => models.isEmpty;

  /// An external server that is actually answering.
  bool get hasRunningServer =>
      backends.any((backend) => backend.isExternal && backend.running);

  List<ShareRouteOffer> get offers => buildShareRouteOffers(
    canRunLocal: canRunLocal,
    needsModel: needsModel,
    keyProviders: [
      for (final offer in keyProviders) offer.provider.label,
    ],
    backends: backends,
  );

  ShareRoute get defaultRoute => defaultShareRoute(
    canRunLocal: canRunLocal,
    serverFound: backends.any((backend) => backend.isExternal),
    hasKeyProvider: keyProviders.isNotEmpty,
  );
}

/// Probes this computer once.
///
/// The three slow parts — the HTTP backend probes and the CLI's catalog spawns
/// — run concurrently, because they are independent and the page is waiting on
/// all of them.
Future<ShareCapabilities> discoverShareCapabilities(GridCli cli) async {
  if (await cli.locate() == null) return ShareCapabilities.empty;
  final backends = BackendDetector().detect();
  final providers = discoverKeyProviders(cli);
  return ShareCapabilities(
    cliInstalled: true,
    engineInstalled: GridPaths.llamaServerBin.existsSync(),
    models: readLocalModels(),
    backends: await backends,
    keyProviders: await providers,
  );
}

/// A model's maximum context window, read from its GGUF metadata.
///
/// Bounds the memory slider, so it can never offer a window the model cannot
/// hold — a join with `--ctx-size` above the maximum is refused by llama.cpp,
/// and the failure arrives well after the press that caused it.
///
/// Falls back to [defaultContextTarget]'s own ceiling when the CLI cannot read
/// the file: an unreadable header is not a reason to refuse to serve, and the
/// engine clamps what it is given anyway.
Future<int> readMaxContext(GridCli cli, String modelFile) async {
  final result = await cli.runJson<Map<String, dynamic>>(['ctx', modelFile]);
  final value = result?['context_length'];
  if (value is int && value >= minContextTokens) return value;
  return defaultContextLength(1 << 20);
}

/// Starts Ollama's own server and waits for it to answer.
///
/// The route offers this because "installed but not running" is the state most
/// machines with Ollama are in, and the alternative is telling somebody to go
/// and open a terminal. Detached: this app is not Ollama's supervisor, and a
/// server that died when the window closed would be a worse answer than not
/// offering it.
Future<bool> startOllamaServer({
  Duration timeout = const Duration(seconds: 20),
}) async {
  try {
    await Process.start('ollama', [
      'serve',
    ], mode: ProcessStartMode.detached, runInShell: true);
  } on ProcessException {
    return false;
  }
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await BackendDetector.isServerUp(BackendDetector.ollamaBase)) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  return false;
}
