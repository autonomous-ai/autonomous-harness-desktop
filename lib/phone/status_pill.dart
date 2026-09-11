import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart';
import 'phone_status.dart';

/// The palette colour a [PhoneTone] draws in.
Color phoneToneColor(PhoneTone tone) => switch (tone) {
  PhoneTone.good => AppPalette.online,
  PhoneTone.busy => AppPalette.accent,
  PhoneTone.attention => AppPalette.warn,
  PhoneTone.bad => AppPalette.offline,
  PhoneTone.quiet => AppPalette.textFaint,
};

/// A status line: a dot — a small spinner while something is under way — and its label.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.summary, this.fontSize = 13});

  final PhoneSummary summary;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final color = phoneToneColor(summary.tone);
    final quiet = summary.tone == PhoneTone.quiet;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 10,
          child: summary.tone == PhoneTone.busy
              ? CircularProgressIndicator(strokeWidth: 1.6, color: color)
              : Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox.square(dimension: 8),
                  ),
                ),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            summary.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: quiet ? AppPalette.textSecondary : color,
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
