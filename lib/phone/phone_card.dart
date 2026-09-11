import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart';
import '../shared/widgets/skeleton.dart';

/// The gap between two cards in a phone list.
const double kPhoneCardGap = 10;

/// A phone card row's height: a 44pt glyph plus its padding. The skeleton is drawn at exactly
/// this, so a list that answers does not jump.
const double kPhoneCardHeight = 70;

/// A phone list's padding: clear of the screen edges, and of the home indicator at the bottom.
EdgeInsets phoneListPadding(BuildContext context) =>
    EdgeInsets.fromLTRB(16, 4, 16, MediaQuery.paddingOf(context).bottom + 24);

/// A tappable row on the phone: a glass card that sinks a little under the finger. Without an
/// [onTap] it is drawn dimmed and does not move.
class PhoneCard extends StatefulWidget {
  const PhoneCard({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<PhoneCard> createState() => _PhoneCardState();
}

class _PhoneCardState extends State<PhoneCard> {
  bool _pressed = false;

  void _press(bool pressed) {
    if (widget.onTap == null || _pressed == pressed) return;
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _press(true),
      onTapUp: (_) => _press(false),
      onTapCancel: () => _press(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.975 : 1,
        duration: AppMotion.press,
        curve: AppMotion.curve,
        child: AnimatedContainer(
          duration: AppMotion.press,
          curve: AppMotion.curve,
          height: kPhoneCardHeight,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: _pressed ? AppGlass.rowHoverFill : AppGlass.rowFill,
            borderRadius: BorderRadius.circular(AppCard.radius),
            border: Border.all(color: AppGlass.hair),
          ),
          child: Opacity(
            opacity: widget.onTap == null ? 0.55 : 1,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// The square glyph at the head of a card — a machine's screen, an agent's engine mark.
class PhoneCardGlyph extends StatelessWidget {
  const PhoneCardGlyph({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppSurface.recess,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(child: child),
    );
  }
}

/// A pull-to-refresh list of cards, laid out the one way every phone list is.
class PhoneCardList extends StatelessWidget {
  const PhoneCardList({
    super.key,
    required this.onRefresh,
    required this.itemCount,
    required this.itemBuilder,
  });

  final Future<void> Function() onRefresh;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: onRefresh,
    child: ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: phoneListPadding(context),
      itemCount: itemCount,
      separatorBuilder: (_, _) => const SizedBox(height: kPhoneCardGap),
      itemBuilder: itemBuilder,
    ),
  );
}

/// A list of cards that has not answered yet: the same cards, empty, at a real row's height.
class PhoneListSkeleton extends StatelessWidget {
  const PhoneListSkeleton({super.key, this.rows = 3});

  final int rows;

  @override
  Widget build(BuildContext context) => ListView.separated(
    physics: const NeverScrollableScrollPhysics(),
    padding: phoneListPadding(context),
    itemCount: rows,
    separatorBuilder: (_, _) => const SizedBox(height: kPhoneCardGap),
    itemBuilder: (_, _) => const Skeleton(
      width: double.infinity,
      height: kPhoneCardHeight,
      radius: AppCard.radius,
    ),
  );
}
