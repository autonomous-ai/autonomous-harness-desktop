/// Turning a catalogue version into the `grid pull` commands that fetch it.
library;

/// A Hugging Face download URL:
/// `https://huggingface.co/<owner>/<repo>/resolve/<ref>/<path-in-repo>`.
/// Group 1 is the repo id, group 2 the path inside it — the two halves of the
/// `<repo>:<file>` spec `grid pull` takes.
final _hfResolveUrl = RegExp(
  r'^https?://huggingface\.co/([^/]+/[^/]+)/resolve/[^/]+/(.+)$',
  caseSensitive: false,
);

/// Every spec needed to download one version — one per file.
///
/// A split GGUF is several files and the catalogue's `pull_spec` names only the
/// first, so pulling that alone leaves a model the engine cannot load. The
/// parts are all in `urls`, so a spec is derived from each.
///
/// Falls back to [pullSpec] when a URL is not a Hugging Face one: there is no
/// spec to build from a shape we do not recognise, and pulling the subset we
/// did recognise would quietly produce a model with a hole in it.
List<String> versionPullSpecs({
  required List<String> urls,
  required String? pullSpec,
}) {
  final specs = <String>[];
  for (final url in urls) {
    final match = _hfResolveUrl.firstMatch(url.trim());
    if (match == null) return _onlySpec(pullSpec);
    specs.add('${match.group(1)}:${match.group(2)}');
  }
  return specs.isEmpty ? _onlySpec(pullSpec) : specs;
}

List<String> _onlySpec(String? pullSpec) {
  final spec = pullSpec?.trim() ?? '';
  return spec.isEmpty ? const [] : [spec];
}

/// The filename `grid pull <spec>` lands on disk, or null when [spec] carries
/// no usable file half.
///
/// The CLI stores every download flat in `~/.grid/models`, so the folder a
/// catalogue spec names (`…-GGUF:UD-IQ1_M/model-00001-of-00003.gguf`) never
/// reaches the disk. Comparing on-disk names against the un-stripped path is
/// why a download that worked used to report "couldn't be found afterwards".
String? pullSpecFileName(String spec) {
  final colon = spec.indexOf(':');
  if (colon < 0) return null;
  final path = spec.substring(colon + 1).trim();
  final slash = path.lastIndexOf('/');
  final name = slash < 0 ? path : path.substring(slash + 1);
  return name.isEmpty ? null : name;
}

/// Strips a name to what survives a download: lowercase, letters and digits.
/// `Qwen2.5-3B-Instruct-GGUF` and `qwen2.5-3b-instruct-q4_k_m.gguf` differ in
/// punctuation and quant, but both reduce to a form where one contains the
/// other.
String _installKey(String value) =>
    value.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

/// Whether a catalogue model is already under `~/.grid/models`.
///
/// Two ways to match, because the two catalogue shapes carry different facts. A
/// version — and a `grid catalog` recommendation — names the exact [file] it
/// downloads, so that is an equality test and the certain answer. A shelf entry
/// knows only its repo id, so it asks instead whether any local filename reads
/// as coming from that repo.
///
/// The fallback is deliberately *model*-level rather than file-level: having a
/// different quant of the same model still means the answer to "do I have this
/// one?" is yes, and listing it as missing would send somebody to download a
/// second copy.
///
/// It also tries the repo stem with its last segment dropped, because a repo
/// name carries words a filename does not: `Qwen3.6-35B-A3B-MTP-GGUF` is
/// downloaded as `Qwen3.6-35B-A3B-UD-IQ3_S.gguf`, and the exact stem misses it.
/// Short stems are refused either way — three characters match half the shelf
/// by accident.
bool isCatalogModelInstalled({
  required String repoId,
  String? file,
  required Iterable<String> localFileNames,
}) {
  final local = [for (final name in localFileNames) name.toLowerCase()];
  if (file != null && file.isNotEmpty && local.contains(file.toLowerCase())) {
    return true;
  }
  final keys = [for (final name in local) _installKey(name)];
  for (final stem in _repoStems(repoId)) {
    if (keys.any((name) => name.contains(stem))) return true;
  }
  return false;
}

/// The forms of a repo name worth looking for in a filename, longest first.
List<String> _repoStems(String repoId) {
  final tail = repoId.contains('/') ? repoId.split('/').last : repoId;
  final base = tail.replaceAll(RegExp(r'[-_]?gguf$', caseSensitive: false), '');
  final segments = base.split(RegExp(r'[-_]'));
  final candidates = <String>[base];
  // One segment dropped, and no more: two would leave "Qwen3.6" matching every
  // Qwen on the shelf.
  if (segments.length > 1) {
    candidates.add(segments.sublist(0, segments.length - 1).join('-'));
  }
  return [
    for (final candidate in candidates)
      if (_installKey(candidate).length >= 6) _installKey(candidate),
  ];
}
