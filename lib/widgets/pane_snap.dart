import 'package:flutter/services.dart';

/// Where a dragged divider prefers to land.
///
/// A boundary set by hand almost always WANTS a plain ratio — half, a third,
/// two thirds — and lands a pixel or two off it, which is invisible in the
/// moment and permanent afterwards. Snapping makes the common intent free and
/// costs nothing else: hold shift and the raw position is kept.
///
/// The golden section is in the list on purpose. It is the one irrational ratio
/// people actually reach for, and it sits far enough from 3/5 (0.600 against
/// 0.618) that both are reachable rather than one swallowing the other.
const _ratios = <double>[
  1 / 5,
  1 / 4,
  1 / 3,
  0.382,
  2 / 5,
  1 / 2,
  3 / 5,
  0.618,
  2 / 3,
  3 / 4,
  4 / 5,
];

/// How close the boundary has to be, in PIXELS rather than in fraction.
///
/// A fraction threshold behaves differently on every window: eight thousandths
/// of a 2560px display is 20px of dead zone, and of a 900px one is 7px. The
/// hand is working in pixels, so the tolerance is too.
const double _snapRadiusPx = 7;

/// Snap `fraction` to a nearby plain ratio, unless shift says not to.
///
/// `spanPx` is the width or height the fraction divides — the pair either side
/// of this one boundary, not the whole axis, so the feel does not change with
/// how many tiles happen to be beside it.
double snapFraction(double fraction, double spanPx) {
  if (HardwareKeyboard.instance.isShiftPressed) return fraction;
  if (!spanPx.isFinite || spanPx <= 0) return fraction;
  final radius = _snapRadiusPx / spanPx;
  var best = fraction;
  var bestGap = radius;
  for (final ratio in _ratios) {
    final gap = (fraction - ratio).abs();
    if (gap < bestGap) {
      bestGap = gap;
      best = ratio;
    }
  }
  return best;
}
