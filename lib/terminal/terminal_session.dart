import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import '../core/crash_log.dart';
import 'terminal_binary.dart';
import 'terminal_viewport.dart';

typedef TerminalFrameSender = Future<bool> Function(
  String type,
  Map<String, dynamic> payload,
);
typedef TerminalBinarySender = Future<bool> Function(TerminalBinaryFrame frame);

enum TerminalSessionStatus {
  closed,
  opening,
  controlling,
  resyncing,
  takenOver,
  error,
}

/// One controller stream for one remote Harness agent.
///
/// Sequence corruption is recovered with bounded resync retries and one clean
/// reopen. Transport loss still freezes input until the user opens a session.
class TerminalSession extends ChangeNotifier {
  static const protocolVersion = 3;
  static const minCols = 40;
  static const maxCols = 300;
  static const minRows = 12;
  static const maxRows = 120;

  final String machineId;
  final String agentId;
  String agentName;
  final String? engineId;
  final TerminalFrameSender send;
  final TerminalBinarySender sendBinary;
  final Duration resyncTimeout;

  /// Forces a fresh transport dial (see `WsConn.forceReconnect`) — called once when the very first
  /// `terminal_open` never gets a `terminal_ready` back within [resyncTimeout]. Covers the relay
  /// going stale silently (the relayed machine's own Harness process restarted, dropping its E2EE
  /// session without the transport ever closing) so a reconnect looks like a couple of extra seconds
  /// of "attaching" instead of a hang the user has to notice and manually retry.
  final Future<void> Function()? onOpenStalled;

  TerminalSession({
    required this.machineId,
    required this.agentId,
    required this.agentName,
    required this.engineId,
    required this.send,
    required this.sendBinary,
    this.onOpenStalled,
    this.resyncTimeout = const Duration(seconds: 4),
  }) {
    terminal = _newTerminal();
  }

  late Terminal terminal;
  TerminalSessionStatus status = TerminalSessionStatus.closed;
  String? streamId;
  String? errorCode;
  String? errorMessage;
  int cols = 80;
  int rows = 24;

  String? _openRequestId;
  int? _expectedSeq;
  int _lastRenderedSeq = -1;
  int _framesSinceAck = 0;
  int _renderedSinceAckBytes = 0;
  int _inputSeq = 0;
  int _resizeSeq = 0;
  bool _resyncRequested = false;
  int _resyncAttempts = 0;
  int _autoReopenAttempts = 0;
  bool _openStallRecovered = false;
  bool _disposed = false;
  bool _remoteCursorVisible = true;
  bool _cursorBlinkPhaseVisible = true;
  List<int> _utf8Tail = const [];
  final List<int> _inputBytes = [];
  Timer? _heartbeat;
  Timer? _ackTimer;
  Timer? _inputTimer;
  Timer? _resizeTimer;
  DateTime? _lastInputFlushAt;
  DateTime? _lastResizeFlushAt;
  Timer? _resyncTimer;
  Timer? _scrollTimer;
  bool? _pendingScrollUp;
  int _pendingScrollLines = 0;
  int? _pendingCols;
  int? _pendingRows;
  TerminalViewport? _viewport;
  final Completer<({int cols, int rows})> _viewportSize = Completer();
  Future<void> _renderTail = Future<void>.value();
  Future<void> _inputSendTail = Future<void>.value();

  bool get acceptsInput =>
      status == TerminalSessionStatus.controlling && streamId != null;

  /// Grok's CLI declares terminal mouse-tracking (so tmux defers wheel bytes to it, same as any
  /// alt-buffer program) but doesn't correctly handle wheel reports itself — confirmed live: it
  /// echoes the raw SGR escape bytes into its own prompt as literal characters instead of
  /// scrolling. Its alt-buffer scroll gestures route through the daemon's tmux copy-mode
  /// (`sendScrollCommand`/`terminal_scroll`) instead of the raw `mouseInput` path every other
  /// engine already uses correctly.
  bool get scrollViaTmuxCopyMode => engineId == 'grok';

  void renameAgent(String name) {
    final cleanName = name.trim();
    if (cleanName.isEmpty || cleanName == agentName) return;
    agentName = cleanName;
    notifyListeners();
  }

  Future<void> open({
    int initialCols = 80,
    int initialRows = 24,
    bool waitForViewportSize = false,
  }) => _open(
    initialCols: initialCols,
    initialRows: initialRows,
    waitForViewportSize: waitForViewportSize,
    resetRecovery: true,
  );

  Future<void> _open({
    required int initialCols,
    required int initialRows,
    required bool waitForViewportSize,
    required bool resetRecovery,
  }) async {
    _cancelTimers();
    streamId = null;
    errorCode = null;
    errorMessage = null;
    _expectedSeq = null;
    _lastRenderedSeq = -1;
    _framesSinceAck = 0;
    _renderedSinceAckBytes = 0;
    _inputSeq = 0;
    _resizeSeq = 0;
    _utf8Tail = const [];
    _remoteCursorVisible = true;
    _cursorBlinkPhaseVisible = true;
    _resyncRequested = false;
    _resyncAttempts = 0;
    if (resetRecovery) {
      _autoReopenAttempts = 0;
      _openStallRecovered = false;
    }
    cols = _clampCols(initialCols);
    rows = _clampRows(initialRows);
    terminal = _newTerminal()..resize(cols, rows);
    status = TerminalSessionStatus.opening;
    _openRequestId =
        'term_${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 31)}';
    notifyListeners();

    if (waitForViewportSize) {
      try {
        final measured = await _viewportSize.future.timeout(
          const Duration(seconds: 2),
        );
        cols = _clampCols(measured.cols);
        rows = _clampRows(measured.rows);
        terminal.resize(cols, rows);
        notifyListeners();
      } on TimeoutException {
        // Keep the conservative fallback when the terminal viewport cannot be
        // measured; the normal resize path will reconcile it after attach.
      }
    }

    final openPayload = {
      'protocolVersion': protocolVersion,
      'requestId': _openRequestId,
      'agentId': agentId,
      'cols': cols,
      'rows': rows,
      'compression': const ['zlib', 'none'],
    };
    var sent = await send('terminal_open', openPayload);
    if (!sent) {
      // Most commonly transient: the local transport is mid-reconnect at this exact instant (e.g.
      // right after the app itself just started, or another machine's relay hiccupped a moment ago).
      sent = await _recoverAndResend(openPayload);
    }
    if (!sent) {
      transportLost('Could not send terminal_open');
      return;
    }
    // Armed unconditionally (not just on reopen attempts): a `terminal_open` sent through a silently
    // stale relay session never gets ANY reply — nothing else would ever notice or recover from that.
    _resyncTimer?.cancel();
    _resyncTimer = Timer(
      resyncTimeout,
      () => unawaited(_handleOpenTimeout(openPayload)),
    );
  }

  /// The armed-on-every-open watchdog fired: no `terminal_ready` arrived in time even though the send
  /// itself succeeded — the relay session was silently stale (ciphertext for a dead E2EE session gets
  /// dropped, not rejected). Force a fresh dial and resend the SAME open request (same `requestId`, so
  /// a late reply for the original still matches) before giving up.
  Future<void> _handleOpenTimeout(Map<String, dynamic> openPayload) async {
    if (status != TerminalSessionStatus.opening || streamId != null) return;
    final sent = await _recoverAndResend(openPayload);
    if (sent) {
      _resyncTimer?.cancel();
      _resyncTimer = Timer(
        resyncTimeout,
        () => unawaited(_handleOpenTimeout(openPayload)),
      );
      return;
    }
    _fail(
      'TERMINAL_RESYNC_TIMEOUT',
      _autoReopenAttempts > 0
          ? 'Terminal did not reopen after resync failed.'
          : 'Harness did not respond — check your connection.',
    );
  }

  /// Shared recovery for both open-failure paths (`send()` itself failing, and `terminal_ready` never
  /// arriving): force a fresh transport dial (see `WsConn.forceReconnect`), then poll-resend — a forced
  /// relay redial is a REAL network round trip (fresh E2EE handshake for a relayed machine), and
  /// `forceReconnect()` resolving only means the redial STARTED, not that the transport is ready again.
  /// Bounded by [_openStallRecovered] (one forced reconnect per open) and a fixed poll budget, so a
  /// persistently broken connection still fails closed instead of retrying forever.
  Future<bool> _recoverAndResend(Map<String, dynamic> openPayload) async {
    final recover = onOpenStalled;
    if (_openStallRecovered || recover == null) return false;
    _openStallRecovered = true;
    try {
      await recover();
    } catch (_) {
      // Still worth polling for readiness even if the forced reconnect itself errored.
    }
    for (var attempt = 0; attempt < 10; attempt++) {
      if (_disposed || status != TerminalSessionStatus.opening) return false;
      if (await send('terminal_open', openPayload)) return true;
      await Future.delayed(const Duration(milliseconds: 300));
    }
    return false;
  }

  /// Returns true when [type] belongs to this session's protocol.
  Future<bool> handleFrame(String type, Map<String, dynamic> payload) async {
    switch (type) {
      case 'terminal_ready':
        if (status != TerminalSessionStatus.opening ||
            payload['requestId'] != _openRequestId ||
            payload['agentId'] != agentId ||
            payload['protocolVersion'] != protocolVersion) {
          return true;
        }
        streamId = payload['streamId'] as String?;
        if (streamId == null || streamId!.isEmpty) {
          _fail('TERMINAL_READY_INVALID', 'Harness returned no stream id');
          return true;
        }
        _resyncTimer?.cancel();
        _resyncTimer = null;
        _heartbeat = Timer.periodic(
          const Duration(seconds: 5),
          (_) => unawaited(_sendHeartbeat()),
        );
        _armInitialKeyframeWatchdog();
        return true;
      case 'terminal_keyframe':
      case 'terminal_output':
        _fail(
          'TERMINAL_BINARY_REQUIRED',
          'Harness sent terminal bulk data as JSON',
        );
        return true;
      case 'terminal_closed':
        if (!_matchesStream(payload)) return true;
        _cancelTimers();
        final code = payload['code']?.toString();
        final takenOver = code == 'TERMINAL_TAKEN_OVER';
        status = takenOver
            ? TerminalSessionStatus.takenOver
            : TerminalSessionStatus.closed;
        errorCode = takenOver ? code : null;
        errorMessage = takenOver
            ? 'Another client connected to this terminal.'
            : payload['reason']?.toString();
        streamId = null;
        notifyListeners();
        return true;
      case 'terminal_error':
        final errorStream = payload['streamId'];
        final errorRequest = payload['requestId'];
        if (errorStream != null && errorStream != streamId) return true;
        if (errorRequest != null && errorRequest != _openRequestId) return true;
        _fail(
          payload['code']?.toString() ?? 'TERMINAL_ERROR',
          payload['message']?.toString(),
        );
        return true;
      case 'terminal_transport_error':
        transportLost(
          payload['code']?.toString() ?? 'Terminal relay rejected the frame',
        );
        return true;
      default:
        return false;
    }
  }

  Future<void> handleBinary(TerminalBinaryFrame frame) async {
    if (frame.streamId != streamId) return;
    _renderTail = _renderTail
        .then((_) async {
          final bytes = _decodeBinaryBytes(frame);
          if (bytes == null) {
            await _requestResync('TERMINAL_BINARY_DECODE_FAILED');
            return;
          }
          if (frame.kind == TerminalBinaryKind.keyframe) {
            final nextCols = frame.cols;
            final nextRows = frame.rows;
            if (nextCols == null || nextRows == null) {
              await _requestResync('TERMINAL_KEYFRAME_INVALID');
              return;
            }
            cols = _clampCols(nextCols);
            rows = _clampRows(nextRows);
            _utf8Tail = const [];
            _remoteCursorVisible = true;
            _cursorBlinkPhaseVisible = true;
            terminal = _newTerminal()..resize(cols, rows);
            if (!_writeBytes(_prepareKeyframeBytes(bytes))) {
              await _requestResync('TERMINAL_UTF8_DECODE_FAILED');
              return;
            }
            _expectedSeq = frame.seq + 1;
            _lastRenderedSeq = frame.seq;
            _resyncRequested = false;
            _resyncAttempts = 0;
            _autoReopenAttempts = 0;
            errorCode = null;
            errorMessage = null;
            _resyncTimer?.cancel();
            _resyncTimer = null;
            status = TerminalSessionStatus.controlling;
            _markForAck(bytes.length);
            notifyListeners();
            return;
          }
          if (frame.kind == TerminalBinaryKind.sync) {
            if (status == TerminalSessionStatus.resyncing) return;
            if (_expectedSeq == null || frame.seq != _expectedSeq) {
              await _requestResync('TERMINAL_SEQUENCE_GAP');
              return;
            }
            _expectedSeq = frame.seq + 1;
            _lastRenderedSeq = frame.seq;
            _markForAck(0);
            return;
          }
          if (frame.kind != TerminalBinaryKind.output ||
              status == TerminalSessionStatus.resyncing) {
            return;
          }
          if (_expectedSeq == null || frame.seq != _expectedSeq) {
            await _requestResync('TERMINAL_SEQUENCE_GAP');
            return;
          }
          if (!_writeBytes(bytes)) {
            await _requestResync('TERMINAL_OUTPUT_DECODE_FAILED');
            return;
          }
          _expectedSeq = frame.seq + 1;
          _lastRenderedSeq = frame.seq;
          _markForAck(bytes.length);
        })
        .catchError((Object error, StackTrace stackTrace) async {
          debugPrint(
            '[terminal-session] renderer failed for '
            '$machineId/$agentId: $error\n$stackTrace',
          );
          CrashLog.record(error, stackTrace, context: 'renderer');
          await onRendererFailure();
        });
    await _renderTail;
  }

  /// Recover from an exception thrown while drawing a frame.
  ///
  /// A renderer fault is LOCAL, and calling it a lost transport was the wrong
  /// diagnosis: the bytes arrived intact and something in drawing them threw.
  /// That froze the tile behind a manual "attach new stream" for a fault the
  /// ordinary resync ladder already clears — it is what the decode failures in
  /// [handleBinary] do — and the ladder is bounded (resync x3, reopen x1, then
  /// a real failure), so a renderer that throws every time still ends up
  /// reporting itself rather than retrying for ever.
  ///
  /// A parser exception can leave the current buffer partially mutated, so the
  /// emulator is not reused: the resync's keyframe is authoritative and
  /// [handleBinary] builds a fresh Terminal for it. Nothing more is written to
  /// the damaged one in the meantime, because the output branch drops frames
  /// while the status is `resyncing`.
  @visibleForTesting
  Future<void> onRendererFailure() =>
      _requestResync('TERMINAL_RENDERER_FAILED');

  Uint8List? _decodeBinaryBytes(TerminalBinaryFrame frame) {
    try {
      return frame.compressed
          ? Uint8List.fromList(ZLibDecoder().convert(frame.bytes))
          : frame.bytes;
    } catch (_) {
      return null;
    }
  }

  void attachViewport(TerminalViewport viewport) {
    _viewport = viewport;
  }

  /// Reports the first grid measured from the actual Flutter terminal render
  /// object. This is deliberately separate from [Terminal.onResize]: creating
  /// a terminal at the conservative 80x24 fallback also fires onResize and
  /// must not be mistaken for a measured viewport.
  void reportViewport(int width, int height) {
    if (_viewportSize.isCompleted) return;
    _viewportSize.complete((cols: _clampCols(width), rows: _clampRows(height)));
  }

  void detachViewport(TerminalViewport viewport) {
    if (identical(_viewport, viewport)) _viewport = null;
  }

  /// Changes only the local paint phase of the cursor. Incoming terminal data
  /// is always parsed against [_remoteCursorVisible], so blinking cannot turn
  /// a remote DECTCEM hide/show command into terminal input or corrupt its
  /// authoritative cursor state.
  void setCursorBlinkPhase(bool visible) {
    if (_cursorBlinkPhaseVisible == visible) return;
    _cursorBlinkPhaseVisible = visible;
    _applyCursorVisibility();
  }

  void _writeTerminalText(String text) {
    terminal.setCursorVisibleMode(_remoteCursorVisible);
    terminal.write(text);
    _remoteCursorVisible = terminal.cursorVisibleMode;
    _applyCursorVisibility();
  }

  void _applyCursorVisibility() {
    terminal.setCursorVisibleMode(
      _remoteCursorVisible && _cursorBlinkPhaseVisible,
    );
  }

  bool _writeBytes(List<int> bytes) {
    final combined = <int>[..._utf8Tail, ...bytes];
    for (
      var tailLength = 0;
      tailLength <= min(3, combined.length);
      tailLength++
    ) {
      try {
        final prefix = combined.sublist(0, combined.length - tailLength);
        final text = utf8.decode(prefix, allowMalformed: false);
        if (text.isNotEmpty) _writeTerminalText(text);
        _utf8Tail = tailLength == 0
            ? const []
            : combined.sublist(combined.length - tailLength);
        return true;
      } catch (_) {
        // A UTF-8 scalar can span at most four bytes; retain only a trailing
        // partial scalar before falling back to replacement rendering below.
      }
    }
    // PTY output is byte-oriented. A snapshot cut can rarely land between the
    // leading and continuation bytes of a scalar, leaving a continuation byte
    // at the start of the post-cut frame. Real terminals render malformed UTF-8
    // as U+FFFD; resyncing the entire screen creates a second keyframe race and
    // cannot recover the missing pre-cut byte anyway.
    final text = utf8.decode(combined, allowMalformed: true);
    if (text.isNotEmpty) _writeTerminalText(text);
    _utf8Tail = const [];
    return true;
  }

  List<int> _prepareKeyframeBytes(Uint8List bytes) {
    if (engineId != 'grok') return bytes;

    // Grok renders a full-screen TUI in tmux's normal buffer. Its tmux
    // scrollback therefore contains old full-screen repaint frames rather than
    // semantic history. Render Grok in the receiver's alternate buffer so the
    // stale frames cannot become local scrollback; wheel input is then routed
    // back to Grok, which owns and redraws its real transcript with ANSI style.
    const alternateBuffer = <int>[
      0x1b,
      0x5b,
      0x3f,
      0x31,
      0x30,
      0x34,
      0x39,
      0x68,
    ];
    if (bytes.length >= 2 && bytes[0] == 0x1b && bytes[1] == 0x63) {
      return <int>[bytes[0], bytes[1], ...alternateBuffer, ...bytes.sublist(2)];
    }
    return <int>[...alternateBuffer, ...bytes];
  }

  Terminal _newTerminal() {
    final result = Terminal(
      maxLines: 10000,
      platform: TerminalTargetPlatform.macos,
      // The remote pane owns its grid and redraws after resize. Reflowing TUI
      // rows locally both changes their geometry and exercises an xterm.dart
      // circular-buffer bug when a remote/local switch changes viewport size.
      reflowEnabled: false,
    );
    result.onOutput = _onTerminalOutput;
    result.onResize = (width, height, _, _) => resize(width, height);
    return result;
  }

  /// Sends a composed message as one turn.
  ///
  /// This does NOT write bytes into the pane. It sends the same `message` frame the web client
  /// uses to drive a turn (`sendMessage` in web's `lib/ws.ts`), and the machine's own handler owns
  /// the injection from there: it adapts slash commands to the pane's engine and retries the
  /// submit Enter. A client typing bytes can do neither — which is exactly how Codex ended up
  /// holding a composed line unsent, its Enter arriving in the same read as the text.
  Future<bool> sendComposerText(String text) async {
    if (!acceptsInput) return false;
    // Ctrl+C is stripped here for the same reason [_onTerminalOutput] strips it: the machine
    // pastes this content into a live pane, where a stray 0x03 is a SIGINT rather than a
    // character, and the engine there has no job-control fallback to survive one.
    final content = text.replaceAll('\x03', '').trimRight();
    if (content.trim().isEmpty) return false;
    return send('message', {
      'content': content,
      'agentId': agentId,
      'mode': 'auto',
    });
  }

  void _onTerminalOutput(String data) {
    if (!acceptsInput || data.isEmpty) return;
    // Ctrl+C (0x03) is never forwarded to the remote pane: the engine CLI
    // there has no local job-control fallback, so a SIGINT that isn't caught
    // in time kills the process outright and drops tmux back to a bare
    // shell instead of just interrupting the current turn.
    if (data.contains('\x03')) {
      data = data.replaceAll('\x03', '');
      if (data.isEmpty) return;
    }
    final bytes = utf8.encode(data);
    final isBoundary =
        data.contains('\r') ||
        data.contains('\x1b[200~') ||
        data.contains('\x1b[201~');
    if (isBoundary) unawaited(_flushInput());
    var offset = 0;
    while (offset < bytes.length) {
      final available = 8 * 1024 - _inputBytes.length;
      final take = min(available, bytes.length - offset);
      _inputBytes.addAll(bytes.sublist(offset, offset + take));
      offset += take;
      if (_inputBytes.length == 8 * 1024) unawaited(_flushInput());
    }
    if (isBoundary) {
      unawaited(_flushInput());
    } else if (_inputBytes.isNotEmpty) {
      // Leading edge: the first keystroke after a pause goes out at once. The window exists to
      // batch key-repeat, and a lone keypress has nothing to batch with — making it wait was
      // 4ms of pure latency on every character typed at human speed. Anything arriving inside
      // the window still rides the trailing timer, so the frame rate stays bounded.
      final last = _lastInputFlushAt;
      final idle =
          last == null ||
          DateTime.now().difference(last) >= _inputCoalesceWindow;
      if (_inputTimer == null && idle) {
        unawaited(_flushInput());
      } else {
        _inputTimer ??= Timer(
          _inputCoalesceWindow,
          () => unawaited(_flushInput()),
        );
      }
    }
  }

  Future<void> _flushInput() async {
    _inputTimer?.cancel();
    _inputTimer = null;
    if (!acceptsInput || _inputBytes.isEmpty) {
      _inputBytes.clear();
      return;
    }
    final bytes = List<int>.from(_inputBytes);
    _inputBytes.clear();
    _lastInputFlushAt = DateTime.now();
    final currentStreamId = streamId;
    if (currentStreamId == null) return;
    final frame = TerminalBinaryFrame(
      kind: TerminalBinaryKind.input,
      streamId: currentStreamId,
      seq: _inputSeq++,
      bytes: Uint8List.fromList(bytes),
      compressed: false,
    );
    final queued = _inputSendTail.then((_) async {
      if (!acceptsInput || streamId != currentStreamId) return;
      final sent = await sendBinary(frame);
      if (!sent) transportLost('Terminal input was not sent');
    });
    _inputSendTail = queued.catchError((_) {
      transportLost('Terminal input was not sent');
    });
    await queued;
  }

  /// A finger on the dial moved — scroll whatever this session is showing.
  ///
  /// Goes STRAIGHT to the renderer rather than through the machine: the scrollback being moved is the copy
  /// in this window, and the agent on the other end has no idea the view scrolled. Nothing is sent over
  /// the wire and nothing is echoed back.
  void scroll(int phase, int dy, int velocity) {
    _viewport?.scroll(phase, dy, velocity);
  }

  /// Coalescing windows for the two things the user drives directly.
  ///
  /// Both are leading + trailing: act on the first event, batch the rest. A flat trailing debounce
  /// charged its full window to every single keystroke and to the start of every drag, which is
  /// latency paid for a batch that mostly never materializes.
  static const _inputCoalesceWindow = Duration(milliseconds: 4);
  static const _resizeCoalesceWindow = Duration(milliseconds: 50);

  void resize(int width, int height) {
    _pendingCols = _clampCols(width);
    _pendingRows = _clampRows(height);
    final last = _lastResizeFlushAt;
    final idle =
        last == null ||
        DateTime.now().difference(last) >= _resizeCoalesceWindow;
    if (_resizeTimer == null && idle) {
      unawaited(_flushResize());
      return;
    }
    // Mid-drag: keep resetting so tmux is asked once, for the size the drag settles on.
    _resizeTimer?.cancel();
    _resizeTimer = Timer(
      _resizeCoalesceWindow,
      () => unawaited(_flushResize()),
    );
  }

  Future<void> _flushResize() async {
    _resizeTimer = null;
    if (!acceptsInput || _pendingCols == null || _pendingRows == null) return;
    final nextCols = _pendingCols!;
    final nextRows = _pendingRows!;
    _pendingCols = null;
    _pendingRows = null;
    if (nextCols == cols && nextRows == rows) return;
    cols = nextCols;
    rows = nextRows;
    _lastResizeFlushAt = DateTime.now();
    final sent = await send('terminal_resize', {
      'streamId': streamId,
      'resizeSeq': _resizeSeq++,
      'cols': cols,
      'rows': rows,
    });
    if (!sent) transportLost('Terminal resize was not sent');
    notifyListeners();
  }

  static const _scrollCoalesceWindow = Duration(milliseconds: 16);

  /// Alt-buffer scroll gesture for a [scrollViaTmuxCopyMode] session — see that getter's doc.
  /// Coalesces rapid deltas (a fast trackpad swipe can emit dozens a second) into one
  /// `terminal_scroll` frame per short burst, mirroring `resize()`'s own debounce. Fire-and-forget
  /// like resize, but a dropped frame here is just a missed scroll, not a transport-health signal —
  /// unlike resize, it never calls `transportLost`.
  void sendScrollCommand(bool up, int lines) {
    if (!scrollViaTmuxCopyMode || lines <= 0) return;
    if (_pendingScrollUp != null && _pendingScrollUp != up) {
      // Direction reversed mid-burst — flush what's accumulated before starting the new direction,
      // rather than let it cancel out into a smaller net scroll the user never asked for.
      unawaited(_flushScrollCommand());
    }
    _pendingScrollUp = up;
    _pendingScrollLines += lines;
    _scrollTimer?.cancel();
    _scrollTimer = Timer(
      _scrollCoalesceWindow,
      () => unawaited(_flushScrollCommand()),
    );
  }

  Future<void> _flushScrollCommand() async {
    _scrollTimer?.cancel();
    _scrollTimer = null;
    final up = _pendingScrollUp;
    final lines = _pendingScrollLines;
    _pendingScrollUp = null;
    _pendingScrollLines = 0;
    if (!acceptsInput || up == null || lines <= 0) return;
    await send('terminal_scroll', {
      'streamId': streamId,
      'direction': up ? 'up' : 'down',
      'lines': lines,
    });
  }

  void _markForAck(int renderedBytes) {
    _framesSinceAck++;
    _renderedSinceAckBytes += renderedBytes;
    if (_renderedSinceAckBytes >= 64 * 1024) {
      unawaited(_flushAck());
      return;
    }
    _ackTimer ??= Timer(
      const Duration(milliseconds: 16),
      () => unawaited(_flushAck()),
    );
  }

  Future<void> _flushAck() async {
    _ackTimer?.cancel();
    _ackTimer = null;
    if (streamId == null || _lastRenderedSeq < 0 || _framesSinceAck == 0) {
      return;
    }
    _framesSinceAck = 0;
    _renderedSinceAckBytes = 0;
    final sent = await send('terminal_ack', {
      'streamId': streamId,
      'lastSeq': _lastRenderedSeq,
    });
    if (!sent) transportLost('Terminal ACK was not sent');
  }

  Future<void> _sendHeartbeat() async {
    if (!acceptsInput) return;
    final sent = await send('terminal_alive', {'streamId': streamId});
    if (!sent) transportLost('Terminal heartbeat was not sent');
  }

  Future<void> _requestResync(String reason) async {
    if (streamId == null) {
      _fail(reason, null);
      return;
    }
    if (!_resyncRequested) {
      _resyncRequested = true;
      _resyncAttempts = 0;
      status = TerminalSessionStatus.resyncing;
      errorCode = reason;
      _inputBytes.clear();
      notifyListeners();
    }
    if (_resyncAttempts > 0) return;
    await _sendResyncAttempt();
  }

  void _armInitialKeyframeWatchdog() {
    _resyncTimer?.cancel();
    _resyncTimer = Timer(resyncTimeout, () {
      if (streamId != null && _expectedSeq == null) {
        unawaited(_requestResync('TERMINAL_KEYFRAME_TIMEOUT'));
      }
    });
  }

  Future<void> _sendResyncAttempt() async {
    final currentStream = streamId;
    if (!_resyncRequested || currentStream == null) return;
    if (_resyncAttempts >= 3) {
      await _recoverByReopen();
      return;
    }
    _resyncAttempts++;
    debugPrint(
      '[terminal-session] resync_request agent=$agentId stream=$currentStream '
      'attempt=$_resyncAttempts code=$errorCode',
    );
    final sent = await send('terminal_resync', {
      'streamId': currentStream,
      'attempt': _resyncAttempts,
      'reason': errorCode,
    });
    if (!sent) {
      transportLost('Could not request terminal resync');
      return;
    }
    _resyncTimer?.cancel();
    _resyncTimer = Timer(resyncTimeout, () {
      if (_resyncRequested && streamId == currentStream) {
        unawaited(_sendResyncAttempt());
      }
    });
  }

  Future<void> _recoverByReopen() async {
    final previousStream = streamId;
    if (_autoReopenAttempts >= 1) {
      debugPrint(
        '[terminal-session] recovery_failed agent=$agentId '
        'stream=$previousStream attempts=$_resyncAttempts',
      );
      _fail(
        'TERMINAL_RESYNC_TIMEOUT',
        'Terminal did not recover after resync and reopen.',
      );
      return;
    }
    _autoReopenAttempts++;
    debugPrint(
      '[terminal-session] recovery_reopen agent=$agentId stream=$previousStream',
    );
    if (previousStream != null) {
      unawaited(send('terminal_close', {'streamId': previousStream}));
    }
    await _open(
      initialCols: cols,
      initialRows: rows,
      waitForViewportSize: false,
      resetRecovery: false,
    );
  }

  Future<void> close() async {
    final closingStream = streamId;
    _cancelTimers();
    _inputBytes.clear();
    streamId = null;
    status = TerminalSessionStatus.closed;
    notifyListeners();
    if (closingStream != null) {
      await send('terminal_close', {'streamId': closingStream});
    }
  }

  void transportLost([
    String message = 'Connection lost. Select the agent to reconnect.',
  ]) {
    if (status == TerminalSessionStatus.closed) return;
    _cancelTimers();
    _inputBytes.clear();
    streamId = null;
    status = TerminalSessionStatus.error;
    errorCode = 'TERMINAL_DISCONNECTED';
    errorMessage = message;
    notifyListeners();
  }

  void _fail(String code, String? message) {
    _cancelTimers();
    _inputBytes.clear();
    streamId = null;
    status = TerminalSessionStatus.error;
    errorCode = code;
    errorMessage = message;
    notifyListeners();
  }

  bool _matchesStream(Map<String, dynamic> payload) =>
      streamId != null && payload['streamId'] == streamId;

  int _clampCols(int value) => value.clamp(minCols, maxCols);
  int _clampRows(int value) => value.clamp(minRows, maxRows);

  void _cancelTimers() {
    _heartbeat?.cancel();
    _heartbeat = null;
    _ackTimer?.cancel();
    _ackTimer = null;
    _inputTimer?.cancel();
    _inputTimer = null;
    _resizeTimer?.cancel();
    _resizeTimer = null;
    _resyncTimer?.cancel();
    _resyncTimer = null;
    _scrollTimer?.cancel();
    _scrollTimer = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelTimers();
    super.dispose();
  }
}
