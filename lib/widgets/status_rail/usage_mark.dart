import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../shared/theme/app_theme.dart' as grid;
import '../../usage/usage_window.dart';

/// The mark that stands for an agent account wherever its usage is printed.
///
/// Drawn rather than picked from the icon set: a generic asterisk and a generic
/// dotted circle are the same two glyphs a dozen other rows in this app could
/// use, so they identified nothing — the strip's whole job here is to say
/// *whose* figures these are, at a glance, at 12px. A drawn mark also carries
/// the one cue an icon font cannot: the account's own colour.
///
/// One widget for both, and one place that knows which is which, because the
/// rail and the panel both draw it and an account that changed shape between
/// the strip and the popover would read as two accounts.
class UsageMark extends StatelessWidget {
  const UsageMark({super.key, required this.provider, this.size = 12});

  final UsageProvider provider;
  final double size;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: switch (provider) {
          UsageProvider.claude => _ClaudeMark(),
          UsageProvider.codex => _CodexMark(grid.AppPalette.textSecondary),
        },
      ),
    );
  }
}

/// Claude's own colour, which is the point of drawing the mark at all.
///
/// One value across both themes rather than a light and a dark: it is the
/// account's colour, not the app's, and it carries on either ground. Kept here
/// beside the mark instead of in `AppPalette`, which is the app's own design
/// system and should not grow a vendor's swatch.
const Color _claudeCoral = Color(0xFFD97757);

/// A burst of tapered rays — narrow at the centre, rounded at the tip.
///
/// Even spacing and an even count, so the mark reads as balanced at 12px where
/// no individual ray is legible; the taper is what keeps it from flattening
/// into the uniform-width asterisk it replaced.
class _ClaudeMark extends CustomPainter {
  static const int _rays = 8;

  /// Where a ray starts, as a fraction of the radius. Not zero: rays that met
  /// at a point would pile eight overlapping wedges into the middle and read
  /// as a blob.
  static const double _innerFraction = 0.16;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final inner = radius * _innerFraction;
    // Sized off the radius so the mark holds its proportions at any size the
    // panel or the rail asks for.
    final tipWidth = radius * 0.30;
    final rootWidth = radius * 0.17;
    final paint = Paint()
      ..color = _claudeCoral
      ..isAntiAlias = true;

    for (var i = 0; i < _rays; i++) {
      final angle = (math.pi * 2 / _rays) * i - math.pi / 2;
      final along = Offset(math.cos(angle), math.sin(angle));
      final across = Offset(-along.dy, along.dx);
      final tip = centre + along * radius - along * (tipWidth / 2);
      final root = centre + along * inner;
      canvas.drawPath(
        Path()..addPolygon([
          root + across * (rootWidth / 2),
          tip + across * (tipWidth / 2),
          tip - across * (tipWidth / 2),
          root - across * (rootWidth / 2),
        ], true),
        paint,
      );
      // The rounded tip, which is what stops eight sharp points reading as a
      // saw blade at this size.
      canvas.drawCircle(tip, tipWidth / 2, paint);
    }
  }

  @override
  bool shouldRepaint(_ClaudeMark oldDelegate) => false;
}

/// A six-fold rosette: one ring, petalled, in the text's own colour.
///
/// Monochrome and theme-following, unlike Claude's: this account's mark has no
/// colour of its own to carry, so it takes the strip's — which is also what
/// keeps it legible when the window flips to dark.
class _CodexMark extends CustomPainter {
  const _CodexMark(this.color);

  final Color color;

  static const int _petals = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    // The ring the petal centres sit on, and how big each petal is. Together
    // they decide how much the petals overlap, which is the whole character of
    // the mark: too little and it is six dots, too much and it is a disc.
    final ringRadius = radius * 0.46;
    final petalRadius = radius * 0.52;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(radius * 0.16, 0.9)
      ..isAntiAlias = true;

    final path = Path();
    for (var i = 0; i < _petals; i++) {
      final angle = (math.pi * 2 / _petals) * i - math.pi / 2;
      final petalCentre =
          centre + Offset(math.cos(angle), math.sin(angle)) * ringRadius;
      path.addOval(Rect.fromCircle(center: petalCentre, radius: petalRadius));
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CodexMark oldDelegate) => oldDelegate.color != color;
}
