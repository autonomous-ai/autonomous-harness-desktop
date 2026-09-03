import 'dart:io';

import 'grid_paths.dart';

/// Which hosted providers already have a credential on this computer.
///
/// `grid join --api <kind>` stores the key it was given in
/// `~/.grid/api_keys.toml` so the detached serve loop can reuse it, which means
/// a second share does not have to ask for the key again — and the form can say
/// so instead of demanding one the machine already has.
///
/// Deliberately a line scan rather than a TOML dependency. The only question
/// asked here is "does this section hold a non-empty credential", the file is
/// the CLI's own flat `[kind]` + `key = "…"`, and **the value is never read** —
/// what comes back is a set of kind names. Pulling a parser in to answer a
/// yes/no would mean this app could read the secret, which it has no reason to
/// be able to do.
Set<String> readStoredApiKinds({File? file}) {
  final source = file ?? File('${GridPaths.home.path}/api_keys.toml');
  if (!source.existsSync()) return const {};
  final kinds = <String>{};
  String? section;
  try {
    for (final raw in source.readAsLinesSync()) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final header = RegExp(r'^\[([^\]]+)\]$').firstMatch(line);
      if (header != null) {
        section = header.group(1)!.trim();
        continue;
      }
      if (section == null) continue;
      // A key-based kind stores its secret under `key`; an OAuth seat has no
      // `key` and carries tokens instead. Either shape means "already here".
      final match = RegExp(
        r'^(key|access_token|refresh_token)\s*=\s*(.+)$',
      ).firstMatch(line);
      if (match == null) continue;
      final value = match.group(2)!.trim().replaceAll(RegExp(r'^"|"$'), '');
      if (value.isNotEmpty) kinds.add(section);
    }
  } on FileSystemException {
    // An unreadable file is not a reason to refuse the form — it just means
    // the key has to be typed, which is the state this started in.
    return const {};
  }
  return kinds;
}
