import 'package:flutter_test/flutter_test.dart';
import 'package:harness/terminal/terminal_links.dart';
import 'package:xterm/xterm.dart';

/// A terminal holding exactly what [text] prints, at [width] columns.
Terminal _printed(String text, {int width = 80}) {
  final terminal = Terminal(maxLines: 50, reflowEnabled: false)
    ..resize(width, 6);
  terminal.buffer.clear();
  terminal.write(text);
  return terminal;
}

String? _urlAt(Terminal terminal, int x, int y) =>
    terminalLinkAt(terminal.buffer, CellOffset(x, y))?.url.toString();

void main() {
  test('finds the URL under the clicked cell, and the cells it covers', () {
    final terminal = _printed('see https://github.com/autonomous-ai now');
    final link = terminalLinkAt(terminal.buffer, const CellOffset(10, 0));

    expect(link?.url.toString(), 'https://github.com/autonomous-ai');
    expect((link!.start.x, link.start.y), (4, 0));
    expect((link.end.x, link.end.y), (36, 0));
  });

  test('answers nothing for the words either side of a URL', () {
    final terminal = _printed('see https://example.com now');

    expect(_urlAt(terminal, 1, 0), isNull);
    expect(_urlAt(terminal, 22, 0), 'https://example.com');
    expect(_urlAt(terminal, 24, 0), isNull);
  });

  test('leaves a sentence\'s closing punctuation out of the URL', () {
    expect(
      _urlAt(_printed('open https://example.com/a.'), 6, 0),
      'https://example.com/a',
    );
    expect(
      _urlAt(_printed('(see https://example.com/x)'), 6, 0),
      'https://example.com/x',
    );
  });

  test('keeps a closing bracket the URL itself opened', () {
    expect(
      _urlAt(_printed('https://en.wikipedia.org/wiki/Dart_(language)'), 0, 0),
      'https://en.wikipedia.org/wiki/Dart_(language)',
    );
  });

  // Whatever a remote program prints lands in this buffer, so a scheme that
  // makes this computer do something is not a link — clicking it does nothing.
  test('offers nothing but http and https', () {
    for (final text in const [
      'file:///etc/passwd',
      'vscode://file/etc/hosts',
      'javascript:alert(1)',
      'ftp://example.com/x',
    ]) {
      expect(_urlAt(_printed(text), 2, 0), isNull, reason: text);
    }
  });

  test('counts a wide character as the two cells it occupies', () {
    // 中 and 文 take two cells each, so the URL starts at column 5 — not at
    // string index 3, which is where it sits in the text.
    final terminal = _printed('中文 https://example.com');
    final link = terminalLinkAt(terminal.buffer, const CellOffset(6, 0));

    expect(link?.url.toString(), 'https://example.com');
    expect((link!.start.x, link.start.y), (5, 0));
  });

  test('keeps a wide character inside a URL as part of it', () {
    // 中 and 文 each leave an empty second cell behind them; reading that cell
    // as a gap would cut the URL off right after 中.
    final terminal = _printed('https://vi.wikipedia.org/wiki/中文');
    final link = terminalLinkAt(terminal.buffer, const CellOffset(0, 0));

    expect(link?.url, Uri.parse('https://vi.wikipedia.org/wiki/中文'));
    expect((link!.end.x, link.end.y), (34, 0));
  });

  test('follows a URL across a soft-wrapped line', () {
    // At 20 columns, 'go ' and the URL's first 17 characters fill row 0 and
    // the other 17 wrap onto row 1 — clicking either half is the same link.
    final terminal = _printed(
      'go https://example.com/very/long/path',
      width: 20,
    );

    for (final cell in const [CellOffset(5, 0), CellOffset(3, 1)]) {
      final link = terminalLinkAt(terminal.buffer, cell);
      expect(link?.url.toString(), 'https://example.com/very/long/path');
      expect((link!.start.x, link.start.y), (3, 0));
      expect((link.end.x, link.end.y), (17, 1));
    }
  });

  test('does not carry a URL past a line the program ended itself', () {
    final terminal = _printed('https://example.com/a\r\nbc');

    expect(_urlAt(terminal, 3, 0), 'https://example.com/a');
    expect(_urlAt(terminal, 1, 1), isNull);
  });
}
