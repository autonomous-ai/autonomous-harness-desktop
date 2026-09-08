# Vendored xterm.dart

This directory contains the MIT-licensed `xterm` 4.0.0 package used by the
desktop app. It is pinned in-tree because that release corrupts
`IndexAwareCircularBuffer` ownership when `Buffer.scrollUp` or
`Buffer.scrollDown` moves line objects through repeated `operator []=` calls.

The local patch adds an atomic same-length `replaceRange` operation and uses it
for vertical scroll regions. This preserves line identity (and selection
anchors) without temporarily storing the same `BufferLine` in multiple slots.
Remove the vendored dependency once the upstream package ships an equivalent
fix and the regression in `test/terminal_session_test.dart` passes against it.

## Local patches

Each of these has to survive an upstream bump — the tests named are what catch
it if one is dropped.

1. **Atomic `replaceRange` for scroll regions** (the reason this copy exists at
   all — see above). Regression: `test/terminal_session_test.dart`.

2. **Backspace is only handed to the native text input client on Apple
   platforms** (`lib/src/terminal_view.dart`). The key is deliberately not
   turned into bytes there, so that an IME can use it internally (Telex types
   `ư` as `u` + backspace + `ư`); macOS returns it as the `deleteBackward:`
   selector over `TextInputClient.performSelectors`. The GTK embedder has no
   such channel method and names `GDK_KEY_BackSpace` explicitly to ignore it —
   correct for an `EditableText`, wrong for the bare `TextInputClient` here —
   so upstream's unconditional version dropped the key entirely on Linux and no
   byte reached the pty. Regression: the macOS/Linux pair in
   `test/terminal_view_interaction_test.dart`.

3. **A Meta chord is left for the app on every platform, not just Apple**
   (`lib/src/terminal_view.dart`). Every shortcut in
   `lib/shortcuts/app_shortcuts.dart` is declared `meta: true`, which is Super
   on Linux; while this was gated on macOS/iOS a focused terminal answered
   Super+key itself and no app shortcut worked with a pane open. Regression:
   `test/terminal_view_interaction_test.dart`.

4. **Erase-left accepts a cursor in the first column**
   (`lib/src/core/buffer/line.dart`, `lib/src/core/buffer/buffer.dart`). `CSI 1 K`
   at column zero previously passed an empty range to `BufferLine.eraseRange`,
   which read cell `-1` while checking a wide-character boundary. The range
   guard now accepts an empty range, and erase-left includes the cursor cell as
   required by its terminal contract. Regression: `test/terminal_session_test.dart`.

5. **String sequences (DCS/APC/PM/SOS) are consumed instead of leaking**
   (`lib/src/core/escape/parser.dart`). `ESC P` had no handler, so its body was
   handed to the text path one fragment at a time. tmux wraps passthrough as
   `ESC P tmux; <body> ESC \` and doubles every ESC inside that body, so a
   program asking the outer terminal for its background colour from inside tmux
   painted `tmux;]11;?` into the pane — seen in Claude Code's theme picker.
   Only ST ends the body: neither the doubled `ESC ESC` nor an inner OSC's BEL
   may terminate it, and a body split across two pty chunks rolls back and waits
   the same way `_consumeOsc` does. Regression: the two string-sequence tests in
   `test/terminal_session_test.dart`.

