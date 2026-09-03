import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../shared/theme/app_theme.dart' as grid;

/// How much of the grid's memory is spoken for, as a ring.
///
/// A ring rather than a number on its own, because "1.7 TB" has no scale to be
/// read against — the question the rail answers here is *what share*, and a
/// share is a shape. Drawn only when there is something honest to draw: an
/// empty circle beside a total would imply a measurement of zero.
class MemoryRing extends StatelessWidget {
  const MemoryRing({super.key, required this.share, this.size = 11});

  /// 0–1.
  final double share;
  final double size;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          share: share.clamp(0, 1),
          track: grid.AppPalette.divider,
          fill: grid.AppPalette.online,
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.share,
    required this.track,
    required this.fill,
  });

  final double share;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.2;
    final rect = Offset.zero & size;
    final centre = rect.center;
    final radius = (size.width - stroke) / 2;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawCircle(centre, radius, base);
    if (share <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      // From the top, clockwise — the direction a dial is read.
      -math.pi / 2,
      2 * math.pi * share,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = fill,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.share != share || old.track != track || old.fill != fill;
}
