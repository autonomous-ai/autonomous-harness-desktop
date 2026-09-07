// Where a dragged boundary lands.
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/widgets/pane_snap.dart';

void main() {
  // snapFraction reads the live keyboard for the shift override, and that needs
  // a binding even in a plain unit test.
  TestWidgetsFlutterBinding.ensureInitialized();

  const span = 1000.0;   // 7px of tolerance is 0.007 of this

  test('a boundary within a few pixels of a plain ratio takes it', () {
    expect(snapFraction(0.503, span), 0.5);
    expect(snapFraction(0.331, span), closeTo(1 / 3, 1e-9));
    expect(snapFraction(0.752, span), 0.75);
  });

  test('a boundary nobody was aiming at is left exactly where it was', () {
    expect(snapFraction(0.44, span), 0.44);
    expect(snapFraction(0.57, span), 0.57);
  });

  test('the golden section is reachable, and so is three fifths beside it', () {
    // 0.600 and 0.618 are 18px apart on this span — close enough that a sloppy
    // radius would let one swallow the other.
    expect(snapFraction(0.616, span), 0.618);
    expect(snapFraction(0.602, span), 0.6);
  });

  test('the same MISS IN PIXELS behaves the same on any span', () {
    // This is the whole reason the tolerance is not a fraction. A 3px miss is
    // the hand being on target, and it snaps whether the span is 400px or
    // 4000px. A fraction threshold would call the same gesture a hit on one
    // display and a miss on another.
    double off(double px, double span) => 0.5 + px / span;
    expect(snapFraction(off(3, 400), 400), 0.5);
    expect(snapFraction(off(3, 4000), 4000), 0.5);

    // And a 20px miss is a miss on both — the user meant somewhere else.
    expect(snapFraction(off(20, 400), 400), isNot(0.5));
    expect(snapFraction(off(20, 4000), 4000), isNot(0.5));
  });

  test('a span that means nothing yet changes nothing', () {
    expect(snapFraction(0.42, 0), 0.42);
    expect(snapFraction(0.42, double.infinity), 0.42);
  });
}
