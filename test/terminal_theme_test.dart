import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/terminal/terminal_theme.dart';
import 'package:xterm/xterm.dart';

void main() {
  test('terminal defaults follow the app brightness', () {
    final light = terminalThemeFor(Brightness.light);
    final dark = terminalThemeFor(Brightness.dark);

    expect(light.background, const Color(0xffffffff));
    expect(light.foreground, const Color(0xff1f2328));
    expect(dark.background, const Color(0xff181818));
    expect(dark.foreground, const Color(0xffffffff));
  });

  test('light ANSI text stays readable on the app surface', () {
    final theme = terminalThemeFor(Brightness.light);
    final colours = <Color>[
      theme.black,
      theme.red,
      theme.green,
      theme.yellow,
      theme.blue,
      theme.magenta,
      theme.cyan,
      theme.white,
      theme.brightBlack,
      theme.brightRed,
      theme.brightGreen,
      theme.brightYellow,
      theme.brightBlue,
      theme.brightMagenta,
      theme.brightCyan,
      theme.brightWhite,
    ];

    for (final colour in colours) {
      expect(
        _contrastRatio(colour, theme.background),
        greaterThanOrEqualTo(4.5),
        reason:
            '${colour.toARGB32().toRadixString(16)} needs readable contrast',
      );
    }
  });

  test('choosing a visual theme does not mutate terminal data', () {
    final terminal = Terminal(maxLines: 20, reflowEnabled: false)
      ..resize(80, 4)
      ..buffer.clear()
      ..write('\x1b[37mordinary ANSI text\x1b[0m');

    final before = terminal.buffer.getText();
    final light = terminalThemeFor(Brightness.light);
    final dark = terminalThemeFor(Brightness.dark);

    expect(light, isNot(same(dark)));
    expect(terminal.buffer.getText(), before);
  });
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
