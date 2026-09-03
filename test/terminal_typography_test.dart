import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/terminal/terminal_typography.dart';
import 'package:xterm/xterm.dart';

void main() {
  test('the default terminal face is the CoreText SF Mono family', () {
    expect(terminalFontFamily, '.AppleSystemUIFontMonospaced');
    expect(terminalFontSize, 13.0);
    expect(terminalFontFallback, const [
      'Menlo',
      'Monaco',
      'Courier New',
      'monospace',
    ]);
  });

  test('ANSI bold uses SF Mono semibold instead of heavy bold', () {
    expect(
      const TerminalStyle().toTextStyle(bold: true).fontWeight,
      FontWeight.w600,
    );
    expect(const TerminalStyle().toTextStyle().fontWeight, FontWeight.normal);
  });
}
