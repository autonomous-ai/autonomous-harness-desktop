/// How a share becomes a `grid join` command line.
///
/// Pure and in one place, because these arguments are the whole contract with
/// the CLI and every one of them is a rule worth pinning: a model that is
/// advertised under the wrong name, a context size above what the engine can
/// hold, or an empty `--name` all fail well after the press that caused them,
/// with a message about something else.
library;

/// A local GGUF, served by the CLI's built-in engine.
///
/// [endpointPort] is picked by us rather than left to the CLI's fixed 8081,
/// which another app on the machine may already hold — the join then aborts
/// with "Port 8081 already in use".
List<String> localJoinArgs({
  required String gridId,
  required String modelFile,
  required int endpointPort,
  required String nodeName,
  String? advertiseAs,
  int? contextSize,
}) => [
  'join',
  gridId,
  '--serve',
  modelFile,
  '--endpoint-port',
  '$endpointPort',
  ..._advertise(advertiseAs),
  ..._context(contextSize),
  '--name',
  nodeName,
];

/// An OpenAI-compatible server already running on this computer.
///
/// [contextLength] null means **unknown**, and then the flag is left off
/// entirely. That is the honest state and the CLI is built for it: with no
/// `--ctx-size` the node advertises no context window at all, so the grid's
/// router treats it as unknown rather than trusting a number nobody measured.
/// Sending a flat default here would make every external engine claim the same
/// window whatever it really serves, and the router chooses nodes on it.
List<String> externalJoinArgs({
  required String gridId,
  required String endpoint,
  required String model,
  required String nodeName,
  String? advertiseAs,
  int? contextLength,
}) => [
  'join',
  gridId,
  '--at',
  endpoint,
  '-m',
  model,
  ..._advertise(advertiseAs),
  ..._context(contextLength),
  '--name',
  nodeName,
];

/// A hosted provider on the user's own key.
///
/// The key is **not** here. It goes in the child's environment, under the
/// provider's own variable, because `ps` is world-readable for the life of a
/// process and a key on a command line is a key every other process can read.
///
/// [models] are advertised whitelist names; empty serves everything the
/// credential can see, which is the CLI's own zero-config default. No
/// `--advertise-as` or `--ctx-size`: the CLI refuses aliasing for API engines,
/// and the vendor owns the context window.
List<String> apiJoinArgs({
  required String gridId,
  required String kind,
  required String nodeName,
  List<String> models = const [],
}) => [
  'join',
  gridId,
  '--api',
  kind,
  for (final model in models) ...['-m', model],
  '--name',
  nodeName,
];

/// Stop one engine, or every engine this machine has on the grid.
///
/// [selector] is what the CLI matches an engine on — an endpoint URL, or a
/// served model name. Without one this leaves the lot, which is the right
/// fallback: a record that carries nothing to match on is one the user can
/// still get out of.
List<String> leaveArgs({required String gridId, String? selector}) => [
  'leave',
  gridId,
  if (selector != null && selector.isNotEmpty) ...['--engine', selector],
];

List<String> _advertise(String? name) =>
    name != null && name.trim().isNotEmpty
    ? ['--advertise-as', name.trim()]
    : const [];

List<String> _context(int? tokens) =>
    tokens != null ? ['--ctx-size', '$tokens'] : const [];
