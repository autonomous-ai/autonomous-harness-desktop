import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// Harness owns the terminal's *default* appearance.
///
/// Terminal streams provide ANSI attributes, not the source application's
/// complete colour scheme.  The default foreground, background, and ANSI ramp
/// must therefore follow Harness's selected appearance.  Explicit ANSI and
/// true-colour cells remain untouched by xterm, so a TUI keeps the colours it
/// deliberately emits.
TerminalTheme terminalThemeFor(Brightness brightness) {
  return switch (brightness) {
    Brightness.light => _lightTerminalTheme,
    Brightness.dark => _darkTerminalTheme,
  };
}

/// A high-contrast light terminal ramp.
///
/// In a light terminal, SGR 37 (white) cannot literally be white: common TUIs
/// use it for ordinary output.  Both white variants are deliberately darkened
/// so ANSI output remains legible on the app's white content surface.
const _lightTerminalTheme = TerminalTheme(
  cursor: Color(0xff1f2328),
  selection: Color(0x332f5bea),
  foreground: Color(0xff1f2328),
  background: Color(0xffffffff),
  black: Color(0xff24292f),
  red: Color(0xffcf222e),
  green: Color(0xff116329),
  yellow: Color(0xff7d4e00),
  blue: Color(0xff0550ae),
  magenta: Color(0xff8250df),
  cyan: Color(0xff1b7c83),
  white: Color(0xff57606a),
  brightBlack: Color(0xff57606a),
  brightRed: Color(0xffa40e26),
  brightGreen: Color(0xff0e5a27),
  brightYellow: Color(0xff633c01),
  brightBlue: Color(0xff0a3069),
  brightMagenta: Color(0xff6639ba),
  brightCyan: Color(0xff0f6a73),
  brightWhite: Color(0xff1f2328),
  searchHitBackground: Color(0x332f5bea),
  searchHitBackgroundCurrent: Color(0x552f5bea),
  searchHitForeground: Color(0xff1f2328),
);

/// The existing dark terminal ramp, placed on Harness's dark content surface.
const _darkTerminalTheme = TerminalTheme(
  cursor: Color(0xffaeafad),
  selection: Color(0xffaeafad),
  foreground: Color(0xffffffff),
  background: Color(0xff181818),
  black: Color(0xff000000),
  red: Color(0xffcd3131),
  green: Color(0xff0dbc79),
  yellow: Color(0xffe5e510),
  blue: Color(0xff2472c8),
  magenta: Color(0xffbc3fbc),
  cyan: Color(0xff11a8cd),
  white: Color(0xffe5e5e5),
  brightBlack: Color(0xff666666),
  brightRed: Color(0xfff14c4c),
  brightGreen: Color(0xff23d18b),
  brightYellow: Color(0xfff5f543),
  brightBlue: Color(0xff3b8eea),
  brightMagenta: Color(0xffd670d6),
  brightCyan: Color(0xff29b8db),
  brightWhite: Color(0xffffffff),
  searchHitBackground: Color(0xffffff2b),
  searchHitBackgroundCurrent: Color(0xff31ff26),
  searchHitForeground: Color(0xff000000),
);
