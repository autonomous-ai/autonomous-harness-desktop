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
