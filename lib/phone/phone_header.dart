import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../shared/theme/app_theme.dart';
import '../shared/widgets/app_icon_button.dart';

/// The top of a phone page, drawn below the status bar and the Dynamic Island rather than into
/// them — the desktop chrome only ever had traffic lights to clear.
///
/// [large] is the first page's big title, the iOS way. Every other page gets a back chevron and
/// a compact title that can carry a [leading] mark and a quieter [subtitle] line.
class PhoneHeader extends StatelessWidget {
  const PhoneHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing = const [],
    this.large = false,
  });

  final String title;
  final Widget? subtitle;
  final Widget? leading;
  final List<Widget> trailing;
  final bool large;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final canPop = !large && Navigator.of(context).canPop();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        canPop ? 6 : 20,
        large ? 14 : 6,
        14,
        large ? 16 : 10,
      ),
      child: Row(
        children: [
          if (canPop) ...[
            AppIconButton(
              icon: LucideIcons.chevronLeft300,
              size: 30,
              tooltip: 'Back',
              color: AppPalette.textPrimary,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 2),
          ],
          if (leading != null) ...[leading!, const SizedBox(width: 10)],
          Expanded(
            child: _Titles(title: title, subtitle: subtitle, large: large),
          ),
          ...trailing,
        ],
      ),
    );
  }
}

class _Titles extends StatelessWidget {
  const _Titles({
    required this.title,
    required this.subtitle,
    required this.large,
  });

  final String title;
  final Widget? subtitle;
  final bool large;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: AppPalette.textPrimary,
          fontSize: large ? 32 : 17,
          fontWeight: large ? FontWeight.w700 : FontWeight.w600,
          letterSpacing: large ? -0.6 : -0.2,
        ),
      ),
      if (subtitle != null)
        Padding(
          padding: EdgeInsets.only(top: large ? 4 : 2),
          child: subtitle,
        ),
    ],
  );
}
