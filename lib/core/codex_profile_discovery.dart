import 'dart:convert';
import 'dart:io';

/// Finds references to Codex state folders, without executing a shell or reading
/// auth.json. This is a bounded reader of literal shell configuration, not a
/// shell interpreter: computed paths remain available through explicit linking.
class CodexProfileDiscovery {
  CodexProfileDiscovery({required this.home, required this.environment});

  final String home;
  final Map<String, String> environment;
  static const _maxFileBytes = 64 * 1024;
  static const _maxFiles = 256;
  static const _maxEntries = 512;
  final _visited = <String>{};
  final _paths = <String>{};
  final _binDirectories = <String>{};
  bool _stopped = false;

  Future<Set<String>> discover() async {
    await _scan().timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        _stopped = true;
      },
    );
    return Set.of(_paths);
  }

  Future<void> _scan() async {
    final variables = <String, String>{
      for (final entry in environment.entries)
        if (entry.value.startsWith('/') || entry.key == 'PATH')
          entry.key: entry.value,
      'HOME': home,
      'PATH': environment['PATH'] ?? '',
    };
    final inherited = environment['CODEX_HOME'];
    if (inherited != null && inherited.startsWith('/')) _paths.add(inherited);
    final config = environment['XDG_CONFIG_HOME'] ?? '$home/.config';
    await _conventionalHomes(home);
    await _conventionalHomes(config);

    // Finder does not inherit the user's shell PATH. Include its usual private
    // bin locations and read startup files directly instead of sourcing them.
    _binDirectories.addAll(['$home/.local/bin', '$home/bin']);
    await _readShell('$home/.zshenv', variables, 0);
    final zdot = variables['ZDOTDIR'] ?? home;
    for (final path in {
      '$zdot/.zshenv',
      '$zdot/.zprofile',
      '$zdot/.zshrc',
      '$zdot/.zlogin',
      '$home/.profile',
      '$home/.bash_profile',
      '$home/.bash_login',
      '$home/.bashrc',
      '$home/.bash_aliases',
      '$config/fish/config.fish',
    }) {
      await _readShell(path, variables, 0);
    }
    for (final folder in ['$config/fish/conf.d', '$config/fish/functions']) {
      for (final entry in await _entries(folder)) {
        if (entry.path.endsWith('.fish')) {
          await _readShell(entry.path, variables, 0);
        }
      }
    }
    _addBinDirectories(environment['PATH']);
    // Files explicitly referenced by aliases/source have priority over a PATH
    // full of unrelated tools. A huge tool installation must not stall a dialog.
    for (final folder in _binDirectories.toList().take(24)) {
      for (final entry in await _entries(folder)) {
        if (_visited.length >= _maxFiles) break;
        await _readShell(entry.path, Map.of(variables), 0, executable: true);
      }
    }
  }

  Future<List<FileSystemEntity>> _entries(String path) async {
    if (_stopped) return const [];
    try {
      return await Directory(path)
          .list(followLinks: false)
          .take(_maxEntries)
          .toList();
    } on FileSystemException {
      return const [];
    }
  }

  Future<void> _conventionalHomes(String root) async {
    for (final entry in await _entries(root)) {
      final name = entry.path.split('/').last.replaceFirst(RegExp(r'^\.'), '');
      if (!name.toLowerCase().startsWith('codex')) continue;
      if (await File('${entry.path}/auth.json').exists() ||
          await File('${entry.path}/config.toml').exists()) {
        _paths.add(entry.path);
      }
    }
  }

  void _addBinDirectories(String? path) {
    if (path == null) return;
    _binDirectories.addAll(path.split(':').where((p) => p.startsWith('/')));
  }

  Future<void> _readShell(
    String path,
    Map<String, String> variables,
    int depth, {
    bool executable = false,
  }) async {
    if (_stopped || depth > 4 || _visited.length >= _maxFiles) return;
    // These are Codex data, never configuration scripts to inspect.
    if (_isDataFile(path)) return;
    try {
      final file = File(path);
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file || stat.size > _maxFileBytes) {
        return;
      }
      if (executable && stat.mode & 0x49 == 0) return;
      final resolved = await file.resolveSymbolicLinks();
      if (_isDataFile(resolved)) return;
      if (!_visited.add(resolved)) return;
      // Cap the read too: a file can grow after stat. No named pipes/devices.
      final bytes = await file
          .openRead(0, _maxFileBytes + 1)
          .expand((b) => b)
          .toList();
      if (bytes.length > _maxFileBytes || bytes.contains(0)) return;
      final content = utf8.decode(bytes, allowMalformed: false);
      if (executable &&
          !RegExp(r'^#![^\n]*\b(?:ba|z|fi|da|k)?sh\b').hasMatch(content)) {
        return;
      }
      await _readCommands(content, variables, depth);
    } on FileSystemException {
      // A missing, unreadable or broken link does not hide the other profiles.
    } on FormatException {
      // An executable binary is not shell configuration.
    }
  }

  Future<void> _readCommands(
    String content,
    Map<String, String> variables,
    int depth,
  ) async {
    for (final rawCommand in _shellCommands(content)) {
      if (_stopped) return;
      final command = rawCommand
          .skipWhile((word) => word == 'then' || word == 'do')
          .toList();
      if (command.isEmpty) continue;
      final first = _literal(command.first, variables);
      if (first == 'alias') {
        for (final token in command.skip(1)) {
          final match = RegExp(
            r'^[\w-]+=(.*)$',
            dotAll: true,
          ).firstMatch(token);
          if (match == null || depth >= 4) continue;
          final body = _literal(match[1]!, variables);
          if (body != null) {
            await _readCommands(body, Map.of(variables), depth + 1);
          }
        }
        continue;
      }
      if ((first == 'source' || first == '.') && command.length >= 2) {
        final source = _literal(command[1], variables);
        if (source != null && source.startsWith('/')) {
          await _readShell(source, variables, depth + 1);
        }
        continue;
      }
      // fish: set -gx CODEX_HOME /path; set --export CODEX_HOME /path.
      if (first == 'set') {
        final values = command
            .skip(1)
            .where((word) => !word.startsWith('-'))
            .toList();
        if (values.length == 2) {
          _assignment('${values[0]}=${values[1]}', variables);
        }
        continue;
      }
      var prefix = true;
      for (final token in command) {
        if (!prefix) break;
        if (_assignment(token, variables)) continue;
        final word = _literal(token, variables);
        if (const {
              'export',
              'local',
              'declare',
              'typeset',
              'readonly',
              'exec',
              'env',
              'command',
              'then',
              'do',
            }.contains(word) ||
            token.startsWith('-')) {
          continue;
        }
        // Follow literal executable shortcuts, including aliases pointing to a
        // script outside PATH. The script supplies evidence; its name need not
        // mention Codex. Never execute the shortcut to ask it for an answer.
        if (word != null && word.startsWith('/')) {
          await _readShell(
            word,
            Map.of(variables),
            depth + 1,
            executable: true,
          );
        }
        prefix = false;
      }
    }
  }

  bool _assignment(String token, Map<String, String> variables) {
    final raw = RegExp(r'^([A-Za-z_][A-Za-z0-9_]*)=').firstMatch(token);
    final literal = _literal(token, variables);
    final decoded = literal == null
        ? null
        : RegExp(
            r'^([A-Za-z_][A-Za-z0-9_]*)=(.*)$',
            dotAll: true,
          ).firstMatch(literal);
    final name = raw?[1] ?? decoded?[1];
    if (name == null) return false;
    final value = decoded?[2];
    if (value == null) {
      variables.remove(
        name,
      ); // a computed reassignment invalidates the old value
      return true;
    }
    if (name == 'CODEX_HOME' && value.startsWith('/')) _paths.add(value);
    if (name == 'PATH') _addBinDirectories(value);
    if (value.startsWith('/') || name == 'PATH') {
      variables[name] = value;
    } else {
      variables.remove(name);
    }
    return true;
  }
}

bool _isDataFile(String path) => RegExp(
  r'\.(?:jsonl?|toml|sqlite3?|db)$',
  caseSensitive: false,
).hasMatch(path);

/// Keep quotes until interpretation, so '$HOME' stays literal while "$HOME"
/// expands. In an alias the outer quotes are removed before reading its body.
Iterable<List<String>> _shellCommands(String source) sync* {
  final input = source.replaceAll('\\\r\n', '').replaceAll('\\\n', '');
  var words = <String>[];
  var word = StringBuffer();
  String? quote;
  for (var i = 0; i < input.length; i++) {
    final c = input[i];
    if (c == r'\' && quote != "'" && i + 1 < input.length) {
      word.write(c);
      word.write(input[++i]);
      continue;
    }
    if (quote != null) {
      word.write(c);
      if (c == quote) quote = null;
      continue;
    }
    if (c == r'$' && i + 1 < input.length && input[i + 1] == '{') {
      final end = input.indexOf('}', i + 2);
      if (end < 0) return;
      word.write(input.substring(i, end + 1));
      i = end;
      continue;
    }
    if (c == r'$' && i + 1 < input.length && input[i + 1] == '(') {
      // Keep computed expressions opaque, including nested commands, so their
      // contents can never become profile declarations of their own.
      var level = 1;
      final start = i;
      i += 2;
      while (i < input.length && level > 0) {
        if (input[i] == '(') level++;
        if (input[i] == ')') level--;
        i++;
      }
      if (level > 0) return;
      word.write(input.substring(start, i));
      i--;
      continue;
    }
    if (c == "'" || c == '"') {
      quote = c;
      word.write(c);
      continue;
    }
    if (c == '#' && word.isEmpty) {
      while (i < input.length && input[i] != '\n') {
        i++;
      }
      if (words.isNotEmpty) yield words;
      words = [];
      continue;
    }
    if (' \t\r\n;|&(){}'.contains(c)) {
      if (word.isNotEmpty) {
        words.add(word.toString());
        word = StringBuffer();
      }
      if ('\n;|&(){}'.contains(c) && words.isNotEmpty) {
        yield words;
        words = [];
      }
    } else {
      word.write(c);
    }
  }
  if (quote != null) return;
  if (word.isNotEmpty) words.add(word.toString());
  if (words.isNotEmpty) yield words;
}

/// Only literal paths and simple variable references. No command substitution,
/// eval, globbing, parameter operators or positional arguments are interpreted.
String? _literal(String raw, Map<String, String> variables) {
  final out = StringBuffer();
  String? quote;
  for (var i = 0; i < raw.length; i++) {
    final c = raw[i];
    if (c == r'\' && quote != "'") {
      if (++i >= raw.length) return null;
      out.write(raw[i]);
      continue;
    }
    if (c == "'" || c == '"') {
      if (quote == null) {
        quote = c;
        continue;
      }
      if (quote == c) {
        quote = null;
        continue;
      }
    }
    if (quote != "'" && c == r'$') {
      final match = RegExp(
        r'^\$(?:\{([A-Za-z_][A-Za-z0-9_]*)\}|([A-Za-z_][A-Za-z0-9_]*))',
      ).firstMatch(raw.substring(i));
      final value = match == null ? null : variables[match[1] ?? match[2]];
      if (match == null || value == null) return null;
      out.write(value);
      i += match[0]!.length - 1;
      continue;
    }
    if (quote != "'" && c == '`') return null;
    if (quote == null && '*?[]'.contains(c)) return null;
    // Tilde expands only at the start of a word or an assignment's value.
    if (quote == null &&
        c == '~' &&
        (i == 0 || raw[i - 1] == '=') &&
        (i + 1 == raw.length || raw[i + 1] == '/')) {
      out.write(variables['HOME']);
      continue;
    }
    out.write(c);
  }
  return quote == null ? out.toString() : null;
}
