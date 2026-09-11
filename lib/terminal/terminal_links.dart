import 'package:xterm/xterm.dart';

/// A link printed into a terminal, and the cells it covers.
class TerminalLink {
  const TerminalLink({
    required this.url,
    required this.start,
    required this.end,
  });

  final Uri url;

  /// The link's first cell.
  final CellOffset start;

  /// One past its last cell, on the last cell's row.
  final CellOffset end;
}

/// `http(s)://` and then everything up to whitespace or a character no URL carries unescaped.
///
/// Only these two schemes, on purpose: whatever a remote program prints lands in this buffer, so
/// `file:`, `vscode:` and the rest — schemes that make THIS computer do something — are not links.
final _url = RegExp(r'''https?://[^\s<>"'`{}|\\^]+''', caseSensitive: false);

/// Ends a sentence far more often than it ends a URL.
const _trailing = '.,;:!?\'"';

/// The link printed at [cell], or null when there is none.
///
/// Reads the whole LOGICAL line the cell is on — every row a soft wrap continued — so a URL that
/// ran past the right edge is one link from either half. A row the program ended itself is not
/// continued: `isWrapped` is set only by autowrap, never by a newline.
TerminalLink? terminalLinkAt(Buffer buffer, CellOffset cell) {
  final lines = buffer.lines;
  if (cell.y < 0 || cell.y >= lines.length) return null;

  var first = cell.y;
  while (first > 0 && lines[first].isWrapped) {
    first--;
  }
  var last = cell.y;
  while (last + 1 < lines.length && lines[last + 1].isWrapped) {
    last++;
  }

  // The text, and for each UTF-16 unit of it the cell it came from. A wide character is one
  // character in two cells, so an index into the text is not a column.
  final text = StringBuffer();
  final cells = <CellOffset>[];
  var clicked = -1;
  for (var y = first; y <= last; y++) {
    final line = lines[y];
    for (var x = 0; x < line.length; x++) {
      final codePoint = line.getCodePoint(x);
      // The second half of a wide character stores 0; it is not a gap, and not a character.
      if (codePoint == 0 && x > 0 && line.getWidth(x - 1) == 2) continue;
      // A true gap — never written, or skipped over by the cursor — separates words like a space.
      final char = codePoint == 0 ? ' ' : String.fromCharCode(codePoint);
      if (y == cell.y && x <= cell.x) clicked = cells.length;
      for (var i = 0; i < char.length; i++) {
        cells.add(CellOffset(x, y));
      }
      text.write(char);
    }
  }
  if (clicked < 0) return null;

  final source = text.toString();
  for (final match in _url.allMatches(source)) {
    final end = _trimEnd(source, match.start, match.end);
    if (clicked < match.start || clicked >= end) continue;
    final url = Uri.tryParse(source.substring(match.start, end));
    if (url == null || url.host.isEmpty) return null;
    final lastCell = cells[end - 1];
    final lastWidth = lines[lastCell.y].getWidth(lastCell.x);
    return TerminalLink(
      url: url,
      start: cells[match.start],
      end: CellOffset(lastCell.x + (lastWidth < 1 ? 1 : lastWidth), lastCell.y),
    );
  }
  return null;
}

/// Drops what the match swallowed from the prose around it: closing punctuation, and a closing
/// bracket the URL never opened — `(see https://x.dev/a)` — while keeping one it did,
/// `https://en.wikipedia.org/wiki/Dart_(language)`.
int _trimEnd(String text, int start, int end) {
  while (end > start) {
    final last = text[end - 1];
    if (_trailing.contains(last)) {
      end--;
      continue;
    }
    final open = switch (last) {
      ')' => '(',
      ']' => '[',
      _ => null,
    };
    if (open != null) {
      final url = text.substring(start, end);
      if (last.allMatches(url).length > open.allMatches(url).length) {
        end--;
        continue;
      }
    }
    break;
  }
  return end;
}
