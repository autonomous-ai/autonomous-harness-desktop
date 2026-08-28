import 'dart:async';

import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../shared/theme/app_theme.dart' as grid;
import 'link_machine_dialog.dart';
import 'settings_dialog.dart';

class AccountFooter extends StatefulWidget {
  final AppNotifier notifier;

  /// Draw the avatar alone, for the folded rail.
  ///
  /// Not the pill with the email hidden: at 72px a recessed pill would be a
  /// rounded box hugging a circle, which reads as a second ring around the
  /// avatar rather than as a button.
  final bool compact;

  const AccountFooter({
    super.key,
    required this.notifier,
    this.compact = false,
  });

  @override
  State<AccountFooter> createState() => _AccountFooterState();
}

class _AccountFooterState extends State<AccountFooter> {

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final profile = widget.notifier.currentUser;
    final isLocal = widget.notifier.localManualFixture != null;
    final primary =
        profile?.email ?? (isLocal ? 'local terminal' : 'signed in');
    final secondary = isLocal ? 'LOCAL SESSION' : null;

    return MenuAnchor(
      alignmentOffset: const Offset(8, -8),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(grid.AppPalette.cardBg),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shadowColor: WidgetStatePropertyAll(grid.AppSurface.shadow.first.color),
        elevation: const WidgetStatePropertyAll(18),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 8),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(276, 0)),
        maximumSize: const WidgetStatePropertyAll(Size(292, 420)),
        side: WidgetStatePropertyAll(BorderSide(color: grid.AppGlass.hair)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      menuChildren: [
        _AccountSummary(notifier: widget.notifier),
        const Divider(height: 17),
        MenuItemButton(
          key: const Key('link-a-machine-menu-item'),
          leadingIcon: const Icon(Icons.link, size: 18),
          onPressed: () =>
              unawaited(showLinkMachineDialog(context, widget.notifier)),
          child: const Text(
            'Remote into another machine…',
            style: TextStyle(fontSize: 13.5),
          ),
        ),
        const Divider(height: 17),
        MenuItemButton(
          key: const Key('settings-menu-item'),
          leadingIcon: const Icon(Icons.settings, size: 18),
          onPressed: () => unawaited(showSettingsDialog(context)),
          child: const Text('Settings', style: TextStyle(fontSize: 13.5)),
        ),
        const Divider(height: 17),
        MenuItemButton(
          key: const Key('sign-out-menu-item'),
          leadingIcon: const Icon(Icons.logout, size: 18),
          onPressed: () => widget.notifier.logout(),
          child: Text(
            isLocal ? 'Disconnect local session' : 'Sign out',
            style: const TextStyle(fontSize: 13.5),
          ),
        ),
      ],
      builder: (context, controller, child) => Padding(
        // The pill floats inside the rail rather than spanning it. A full-width
        // band with a rule above it reads as a second surface bolted to the
        // bottom; a recessed pill reads as part of the column it sits in.
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        child: widget.compact
            ? Center(
                child: _AvatarButton(
                  onTap: controller.isOpen ? controller.close : controller.open,
                  initials: profile?.initials ?? (isLocal ? 'L' : '?'),
                ),
              )
            : _AccountPill(
                open: controller.isOpen,
                onTap: controller.isOpen ? controller.close : controller.open,
                initials: profile?.initials ?? (isLocal ? 'L' : '?'),
                primary: primary,
                secondary: secondary,
              ),
      ),
    );
  }
}

/// The row you press to reach the account menu.
///
/// Its own widget so the hover state belongs to the thing that shows it: an
/// InkWell `hoverColor` tinted the whole 66px band instead, which read as the
/// rail highlighting rather than the row.
/// The avatar as a button, for the folded rail.
class _AvatarButton extends StatelessWidget {
  const _AvatarButton({required this.onTap, required this.initials});

  final VoidCallback onTap;
  final String initials;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Tooltip(
      message: 'Account',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: const Key('account-menu-button'),
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: _Avatar(initials: initials),
        ),
      ),
    );
  }
}

class _AccountPill extends StatefulWidget {
  const _AccountPill({
    required this.open,
    required this.onTap,
    required this.initials,
    required this.primary,
    this.secondary,
  });

  final bool open;
  final VoidCallback onTap;
  final String initials;
  final String primary;
  final String? secondary;

  @override
  State<_AccountPill> createState() => _AccountPillState();
}

class _AccountPillState extends State<_AccountPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final lit = _hovered || widget.open;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: const Key('account-menu-button'),
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: grid.AppMotion.hover,
          curve: grid.AppMotion.curve,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: lit ? grid.AppSurface.recessHover : grid.AppSurface.recess,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            children: [
              _Avatar(initials: widget.initials),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.primary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: grid.AppPalette.textPrimary,
                        fontFamily: grid.AppFont.sans,
                        fontFamilyFallback: grid.AppFont.sansFallback,
                        fontSize: 13,
                        fontWeight: grid.AppFont.medium,
                      ),
                    ),
                    if (widget.secondary != null)
                      Text(
                        widget.secondary!,
                        style: TextStyle(
                          color: grid.AppPalette.textFaint,
                          fontFamily: grid.AppFont.sans,
                          fontSize: 11,
                          fontWeight: grid.AppFont.medium,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.more_horiz,
                size: 18,
                color: grid.AppPalette.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountSummary extends StatelessWidget {
  final AppNotifier notifier;

  const _AccountSummary({required this.notifier});

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final profile = notifier.currentUser;
    final isLocal = notifier.localManualFixture != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 9, 16, 7),
      child: Row(
        children: [
          _Avatar(
            initials: profile?.initials ?? (isLocal ? 'L' : '?'),
            large: true,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile?.displayName ??
                      (isLocal ? 'Local session' : 'Autonomous user'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: grid.AppPalette.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  profile?.email ??
                      (isLocal ? 'loopback backend' : 'profile unavailable'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: grid.AppPalette.textSecondary,
                    fontSize: 11.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String initials;
  final bool large;

  const _Avatar({required this.initials, this.large = false});

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final size = large ? 36.0 : 32.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // A filled disc, not a ring. The ring read as a third border stacked
        // inside the pill's own rounding; a solid mark is what makes an avatar
        // look like a person rather than like another control.
        color: grid.AppPalette.avatarFill,
        shape: BoxShape.circle,
      ),
      child: Text(
        initials,
        style: TextStyle(
          // White on the accent disc — the token pair the palette is built for
          // (5.5:1). The page ink would be near-black in Light and vanish.
          color: Colors.white,
          fontSize: large ? 12 : 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
