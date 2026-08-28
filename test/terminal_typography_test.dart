import 'package:flutter_test/flutter_test.dart';
import 'package:harness/terminal/terminal_typography.dart';

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
}
