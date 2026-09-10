import 'dart:convert';
import 'dart:io';

import 'engine_endpoint.dart';

/// Which of the engines the app knows how to read answered.
///
/// ⚠️ Named `ProbedEngine` and not `EngineKind`, which this file's Grid-app
/// original calls it: `share/engine_run.dart` already has an `EngineKind`, and
/// it means something else entirely — how a joined engine SERVES (a local GGUF,
/// an external server, a vendor key). Two enums of that name in one `lib/share/`
/// would be a same-word-different-thing collision in the worst place for one.
///
/// Only ever used to decide whether the Model field can offer a list: a
/// recognised engine means its `/models` body was understood, so the names in
/// it can be trusted enough to put in a picker. [unknown] is not a failure —
/// it is every other OpenAI-compatible server, and it gets the plain text field
/// that everyone typing a name by hand already uses.
enum ProbedEngine { ollama, llamaCpp, vllm, unknown }

/// What one look at the engine's `/models` found.
sealed class EngineReach {
  const EngineReach();
}

/// The server answered and named what it serves. [models] may be empty — a
/// server is allowed to answer without listing anything, and that is still a
/// reachable server.
class EngineReachable extends EngineReach {
  const EngineReachable(this.models, this.engine, {this.contextLength});

  final List<String> models;

  /// The context window this server actually serves, when it says so, else
  /// null. Null is a real answer and means "ask the person" — see
  /// [servedContextFrom] for why so few engines qualify.
  final int? contextLength;

  /// Which engine this looked like. [ProbedEngine.unknown] means the body
  /// parsed but carried none of the markers below.
  final ProbedEngine engine;

  /// Whether the Model field can offer a list instead of a text box.
  ///
  /// Both halves are needed. An unrecognised engine may still have handed over
  /// a list of ids — the `data[].id` shape is common to all of them — but a
  /// picker built from a body nobody recognised is a picker that might be
  /// listing the wrong thing, and picking a wrong name is harder to notice than
  /// typing a right one.
  bool get canOfferModels =>
      engine != ProbedEngine.unknown && models.isNotEmpty;
}

/// The server did not answer usefully. [message] is written for the person and
/// **names the URL that was actually called**.
class EngineUnreachable extends EngineReach {
  const EngineUnreachable(this.message);

  final String message;
}

/// How long to wait before calling an address unreachable. Short on purpose:
/// somebody is watching this field while they type into it.
const Duration kEngineProbeTimeout = Duration(seconds: 8);

/// Fetches `<url>` and returns `(status, body)`. Injected so a test can drive
/// every branch below without a socket — the seam `BackendDetector` already
/// uses for the same reason.
typedef EngineFetch = Future<(int, String)> Function(String url);

/// Ask [address] what it serves, so a wrong address fails here rather than two
/// minutes later inside a chat.
///
/// This is the guard the CLI does not have: its own servability check treats an
/// unreachable list as non-breaking, so a node whose address answers nothing
/// still joins, still turns green, and still appears to serve a model.
/// Everything after that fails, and by then the person has left the screen that
/// could have told them.
///
/// Never throws: every outcome is one of the two states above.
Future<EngineReach> probeEngine(
  EngineAddressReady address, {
  EngineFetch? fetch,
}) async {
  final url = address.modelsUrl;
  try {
    final (status, body) = await (fetch ?? _httpFetch)(url);
    if (status != HttpStatus.ok) {
      return EngineUnreachable(_answeredWrong(url, status));
    }
    return EngineReachable(
      modelIdsFrom(body),
      engineFrom(body),
      contextLength: servedContextFrom(body),
    );
  } on Object {
    // Refused, DNS, TLS, timeout — all the same thing to the person reading it:
    // nothing picked up. The distinction belongs in a log, not under a field.
    return EngineUnreachable(
      "Couldn't reach $url — check the address, and that the server is "
      'running.',
    );
  }
}

Future<(int, String)> _httpFetch(String url) async {
  final client = HttpClient()..connectionTimeout = kEngineProbeTimeout;
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close().timeout(kEngineProbeTimeout);
    return (response.statusCode, await response.transform(utf8.decoder).join());
  } finally {
    client.close(force: true);
  }
}

/// The line for a server that answered with something other than 200.
///
/// It names the URL and then *suggests* rather than asserts. A 404 here is
/// usually a missing `/v1`, but not always — some servers do sit at the root,
/// and telling one of those users to add `/v1` sends them to fix a thing that
/// was never wrong.
String _answeredWrong(String url, int status) =>
    '$url answered $status. Many servers need /v1 at the end of the address.';

/// Which engine wrote this `/models` body, as far as the shape gives it away.
///
/// Every one of these serves the same OpenAI envelope, so the engine is only
/// visible in the extra keys each adds to an entry:
///
/// | engine    | marker                                       |
/// |-----------|----------------------------------------------|
/// | vLLM      | `max_model_len` on the entry                 |
/// | llama.cpp | a `meta` object (`n_ctx_train`, `n_params`)  |
/// | Ollama    | `owned_by: "library"`                        |
///
/// Structural markers are checked before `owned_by`, because a field somebody
/// had a reason to add is harder to coincide with than a string.
///
/// TODO(BE): **these markers came across from the Grid app unverified** —
/// neither repo records the shape of a real `/models` body, and no fixture
/// exists to check them against. A wrong marker is not dangerous (it falls to
/// [ProbedEngine.unknown], which is exactly the behaviour before this file — a
/// text field), but it does silently withhold a working picker. Verify with
/// `curl <base>/models` against one of each and pin the bodies as fixtures.
ProbedEngine engineFrom(String body) {
  for (final entry in _entries(body)) {
    if (entry.containsKey('max_model_len')) return ProbedEngine.vllm;
    if (entry['meta'] is Map) return ProbedEngine.llamaCpp;
    final owner = entry['owned_by'];
    if (owner is! String) continue;
    final engine = switch (owner.toLowerCase()) {
      'vllm' => ProbedEngine.vllm,
      'llamacpp' || 'llama.cpp' => ProbedEngine.llamaCpp,
      'library' => ProbedEngine.ollama,
      _ => ProbedEngine.unknown,
    };
    if (engine != ProbedEngine.unknown) return engine;
  }
  return ProbedEngine.unknown;
}

/// The context window this server **serves**, if the body states it outright.
///
/// Deliberately narrow. Only `max_model_len` qualifies — vLLM writes there what
/// it was actually launched with, so it is a fact about the running server.
///
/// llama.cpp's `meta.n_ctx_train` is *not* read, though it sits in the same
/// payload and would be easy to take. It is the window the **model** was
/// trained at, not the one `llama-server` was started with, and those part
/// routinely: a 128k model served at `--ctx-size 8192` would advertise 128k
/// here. Over-advertising is the failure this whole path exists to avoid — the
/// router picks nodes on this number, so an inflated one wins work it then
/// cannot do. Blank is the honest answer, and the person filling the form knows
/// what they launched.
///
/// Ollama and LM Studio both report a window too, but on their own native paths
/// rather than in `/models`. Reading them would mean a second request per
/// engine; the field is there to be typed into meanwhile.
int? servedContextFrom(String body) {
  for (final entry in _entries(body)) {
    final value = entry['max_model_len'];
    if (value is int && value > 0) return value;
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null && parsed > 0) return parsed;
    }
  }
  return null;
}

/// The model ids in an OpenAI-shaped `/models` body, in the order given.
///
/// Lenient by design: this is read from whatever engine the person happens to
/// run, and the only thing riding on it is which names to offer in a dropdown.
/// A body it cannot make sense of yields an empty list, which shows the plain
/// text field — the same place someone typing a name by hand already ends up.
/// It must never throw: the server answered, so the address is good, and a
/// parse quibble is not a reason to refuse the join.
List<String> modelIdsFrom(String body) {
  final ids = <String>[];
  for (final entry in _entries(body)) {
    // `id`, `name`, `model` — the same three keys the Grid CLI's own probe
    // reads. The two are hand-duplicated rather than shared, so they are kept
    // spelled the same on purpose: a picker offering a name the CLI would not
    // have matched is a name the join then fails on.
    final id = entry['id'] ?? entry['name'] ?? entry['model'];
    if (id is String && id.isNotEmpty && !ids.contains(id)) ids.add(id);
  }
  return List.unmodifiable(ids);
}

/// Every object entry in a `/models` body, or empty for anything unreadable.
///
/// `data` is the OpenAI envelope all three serve; `models` is what a couple
/// answer with on their own native path, and costs one line to accept.
List<Map<Object?, Object?>> _entries(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on Object {
    return const [];
  }
  if (decoded is! Map) return const [];
  final entries = decoded['data'] ?? decoded['models'];
  if (entries is! List) return const [];
  return [
    for (final entry in entries)
      if (entry is Map) entry,
  ];
}
