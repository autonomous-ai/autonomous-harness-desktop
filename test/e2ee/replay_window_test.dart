import 'package:flutter_test/flutter_test.dart';
import 'package:harness/e2ee/replay_window.dart';

/// The same cases as the CLI's replayWindow.spec.ts, plus the counters it cannot represent.
void main() {
  test('accepts counters out of order once each, then refuses replays', () {
    final window = ReplayWindow();
    for (final counter in [2, 0, 1]) {
      expect(window.allows(counter), isTrue);
      window.commit(counter);
    }
    expect(window.allows(0), isFalse);
    expect(window.allows(2), isFalse);
  });

  test('refuses counters older than the reordering window', () {
    final window = ReplayWindow()..commit(e2eeReplayWindowSize + 7);
    expect(window.allows(7), isFalse);
    expect(window.allows(8), isTrue);
  });

  test('refuses a counter the CLI could not have sent', () {
    final window = ReplayWindow();
    expect(window.allows(-1), isFalse);
    expect(window.allows(maxSafeInteger + 1), isFalse);
  });
}
