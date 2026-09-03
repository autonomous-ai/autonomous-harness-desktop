import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../grid/managed_network_member.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/app_menu.dart';

/// What somebody may do on a grid — the invite's grant under the address field,
/// and one person's grant at the trailing edge of their row.
///
/// One widget for both, ported from Grid's pair (`invite_role_picker.dart` and
/// `member_role_menu.dart`, over the trigger in `access_menu.dart`). They
/// differed only in [onRemove] and in which edge the panel hangs from, and two
/// widgets for that is how a dialog ends up with two carets of different sizes.
///
/// **Changing a role is one POST**, not DELETE-then-POST: `POST …/members` is
/// an upsert, and the two-call version drops the person off the grid entirely
/// if the second half fails. See [GridApiClient.addMember].
///
/// [roles] is passed in, never read from `ManagedMemberRole.values`: a member
/// may only hand out a role they hold themselves, and that rule belongs to
/// [invitableRolesFor], not to a widget.
///
/// With one role it renders as a plain label rather than vanishing.
/// Disappearing would leave the inviter unable to see WHAT they are granting —
/// the fact that it is not a choice does not make it not worth knowing.
class GridRoleMenu extends StatefulWidget {
  const GridRoleMenu({
    super.key,
    required this.role,
    required this.roles,
    required this.onRoleChanged,
    this.onRemove,
    this.enabled = true,
    this.strong = false,
    this.alignEnd = false,
    this.tooltip,
  });

  /// The grant in force, or null for one the app doesn't name — a grid old
  /// enough to carry the retired `provider` row.
  final ManagedMemberRole? role;

  /// The roles this viewer may hand out. See [invitableRolesFor].
  final List<ManagedMemberRole> roles;

  final ValueChanged<ManagedMemberRole> onRoleChanged;

  /// The destructive row under the divider. Null on a trigger that only picks —
  /// the invite's own, where there is nobody to remove yet.
  final VoidCallback? onRemove;

  final bool enabled;

  /// Heavier label, for the grant an invite is about to hand out — the one
  /// answer in the sheet that has not happened yet.
  final bool strong;

  /// Hang the panel off the trigger's trailing edge, for a trigger sitting at
  /// the right edge of a row where a leftward panel would run out of the sheet.
  final bool alignEnd;

  final String? tooltip;

  /// Wide enough for "They can use every model on this grid, and run one of
  /// their own computers for it." to reach its last word — the clause that says
  /// which of the two roles this is.
  static const double _width = 274;

  @override
  State<GridRoleMenu> createState() => _GridRoleMenuState();
}

class _GridRoleMenuState extends State<GridRoleMenu> {
  final _menu = MenuController();
  bool _hovered = false;

  /// Whether there is anything here to press. A single role with no Remove is a
  /// statement, not a control.
  bool get _actionable =>
      widget.enabled && (widget.roles.length > 1 || widget.onRemove != null);

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final label = widget.role?.label ?? 'Member';
    if (!_actionable) return _StaticLabel(label, strong: widget.strong);

    // The caret rests a step below the label and comes up to meet it under the
    // pointer — the app's standard "fills in on hover", without which the row
    // reads as a printed value rather than a control.
    final caretInk = _hovered
        ? AppPalette.textPrimary
        : AppPalette.textSecondary;

    return MenuAnchor(
      controller: _menu,
      // Right-aligning in LTR takes both halves: `alignment` places the menu's
      // top-LEFT at the named corner of the anchor (Flutter subtracts the child
      // width only in RTL), so the panel is then pulled back by its own width
      // to land its right edge on the trigger's. Exact rather than magic — the
      // width is fixed one field up. The layout still clamps to the screen, so
      // a trigger near the window edge is safe either way.
      alignmentOffset: Offset(widget.alignEnd ? -GridRoleMenu._width : 0, 4),
      style: AppMenu.style(
        minWidth: GridRoleMenu._width,
        maxWidth: GridRoleMenu._width,
      ).copyWith(
        alignment: widget.alignEnd
            ? Alignment.bottomRight
            : Alignment.bottomLeft,
      ),
      menuChildren: [
        for (final option in widget.roles)
          AppMenuItem(
            label: option.label,
            // The exception to this app's label-only menus: "Share a computer"
            // does not say on its own that the person may use the grid's models
            // too, and the two roles are read against each other — [both]'s
            // "That, plus…" only makes sense stacked under [use]'s line.
            detail: option.detail,
            selected: option == widget.role,
            onPressed: () {
              _menu.close();
              // Picking the role they already hold is not a change — sending it
              // would bump their member epoch and make them refresh a token for
              // nothing.
              if (option != widget.role) widget.onRoleChanged(option);
            },
          ),
        if (widget.onRemove case final remove?) ...[
          const AppMenuDivider(),
          AppMenuItem(
            label: 'Remove access',
            danger: true,
            onPressed: () {
              _menu.close();
              remove();
            },
          ),
        ],
      ],
      builder: (context, controller, _) {
        final button = Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppControl.radius),
          child: InkWell(
            onTap: () => controller.isOpen ? controller.close() : controller.open(),
            onHover: (value) => setState(() => _hovered = value),
            borderRadius: BorderRadius.circular(AppControl.radius),
            hoverColor: AppSurface.hoverFill,
            splashFactory: NoSplash.splashFactory,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 7, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppPalette.textPrimary,
                        fontSize: 13,
                        height: 1.2,
                        fontWeight: widget.strong
                            ? AppFont.semibold
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Icon(LucideIcons.chevronDown300, size: 13, color: caretInk),
                ],
              ),
            ),
          ),
        );
        final tooltip = widget.tooltip;
        return tooltip == null
            ? button
            : Tooltip(message: tooltip, child: button);
      },
    );
  }
}

/// The label alone, for a viewer with nothing to choose.
class _StaticLabel extends StatelessWidget {
  const _StaticLabel(this.text, {required this.strong});

  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Padding(
      // Matches the button's text box, so a row doesn't shift by a few pixels
      // depending on who is looking at it.
      padding: const EdgeInsets.fromLTRB(10, 6, 7, 6),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: strong ? AppPalette.textPrimary : AppPalette.textSecondary,
          fontSize: 13,
          height: 1.2,
          fontWeight: strong ? AppFont.semibold : FontWeight.w400,
        ),
      ),
    );
  }
}
