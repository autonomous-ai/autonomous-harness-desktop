import 'context_length.dart';

/// The context sizes offered for a server somebody else started.
///
/// A ladder where the local engine gets a slider, and the reason holds: a
/// server's window is a number it was *launched with*, so the question here is
/// "which of these did you start it on", not "how much would you like". A
/// ladder answers that in one press.
///
/// Two rules keep it honest. Nothing above [max] is offered, because the server
/// cannot serve it. And a value already in force that is not on the ladder —
/// `--ctx-size 40960`, or whatever the server reported about itself — is kept
/// as its own rung, so opening the picker can never quietly round somebody's
/// setting to the nearest familiar number.
List<int> contextLadder({required int max, required int current}) {
  const rungs = [
    4 * 1024,
    8 * 1024,
    16 * 1024,
    32 * 1024,
    64 * 1024,
    128 * 1024,
    200 * 1024,
    256 * 1024,
    512 * 1024,
    1024 * 1024,
  ];
  final ceiling = max < minContextTokens ? minContextTokens : max;
  final offered = {
    for (final rung in rungs)
      if (rung <= ceiling) rung,
    // The ceiling itself, so a server that tops out at an odd number can still
    // be run flat out.
    ceiling,
    // Never drop what is already set.
    current.clamp(minContextTokens, ceiling),
  }.toList()..sort();
  return offered;
}

/// What a server's window is assumed to be when nobody has said.
///
/// 1M is the ladder's top rung, not a claim about any server: the picker has to
/// open on something, and a ceiling that is too generous costs one wrong pick
/// while one that is too mean hides rungs a real server can serve.
const int defaultServerContextCeiling = 1024 * 1024;
