import 'package:flutter/material.dart';

/// Consistent padded frame for a nav section: a title, optional subtitle, and
/// the section body. Reused by every section view.
///
/// Copied from Grid's `shared/widgets/section_scaffold.dart` so a settings
/// screen is laid out identically in both apps — same as the rest of
/// `lib/shared/`. Keep the two in step.
class SectionScaffold extends StatelessWidget {
  const SectionScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.titleTrailing,
  });

  final String title;
  final String? subtitle;

  /// Sits on the heading's baseline, for a pane whose title has a count worth
  /// carrying ("Grid · 4 grids"). Optional, so every other pane is unchanged.
  final Widget? titleTrailing;

  /// Fills the space under the rule, so a body that can outgrow the window
  /// brings its own scroll view.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(title, style: theme.textTheme.headlineSmall),
              if (titleTrailing != null) ...[
                const SizedBox(width: 10),
                Flexible(child: titleTrailing!),
              ],
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
          Expanded(child: child),
        ],
      ),
    );
  }
}
