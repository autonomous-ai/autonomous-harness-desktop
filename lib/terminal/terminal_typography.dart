/// SF Mono's CoreText family name.
///
/// Flutter does not reliably resolve the human-facing `SF Mono` name on macOS;
/// this is the system alias that CoreText resolves to Apple's monospaced face.
///
/// This is the default face — the one `TerminalFontChoice.sfMono` points at
/// (`lib/terminal/terminal_font_store.dart`) and what `reset()` returns to.
/// The live, user-chosen typography lives in `terminalFontStore`, not here.
const terminalFontFamily = '.AppleSystemUIFontMonospaced';

/// The default terminal font size — see `terminalFontFamily`'s doc above.
const terminalFontSize = 13.0;

const terminalFontFallback = <String>[
  'Menlo',
  'Monaco',
  'Courier New',
  'monospace',
];
