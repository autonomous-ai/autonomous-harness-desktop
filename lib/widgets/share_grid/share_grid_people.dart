import 'package:flutter/material.dart';

import '../../grid/grid_members_controller.dart';
import '../../grid/managed_network_member.dart';
import '../../grid/member_display.dart'
    show memberAvatarSlots, memberDomainPart, memberLocalPart, memberStatusLine;
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/member_avatar.dart';
import '../../shared/widgets/skeleton.dart';
import 'grid_role_menu.dart';

/// The "Members" block of the share sheet — everyone already on the grid, what
/// each of them may do, and the way off it.
///
/// Ported from Grid (`features/network/presentation/share_grid_people.dart`),
/// with the Riverpod family swapped for [GridMembersController] and the toasts
/// for [onFailure] — this app has no toast host, and a message about a row
/// belongs beside the row anyway.
///
/// Its own file rather than a section of the dialog: the dialog is three
/// unrelated jobs stacked (invite, list, access rule), and the list is the one
/// with its own async states and its own per-row menu.
class SharePeopleList extends StatelessWidget {
  const SharePeopleList({
    super.key,
    required this.controller,
    required this.canRemove,
    required this.grantable,
    required this.viewerEmail,
    required this.onFailure,
  });

  final GridMembersController controller;

  /// The roles the viewer may hand out — [invitableRolesFor], passed down from
  /// the dialog so the row menu and the invite picker offer the same list. A
  /// widget must not decide this: the rule is the control plane's, and a second
  /// copy of it is one that drifts.
  final List<ManagedMemberRole> grantable;

  /// Whether **the viewer** owns this grid, and so may take somebody's access
  /// away.
  ///
  /// Not to be confused with [ManagedNetworkMember.isOwner], which is about the
  /// person *in a row*. The two read almost the same and mean opposite sides of
  /// the same relationship, so this one is named for the permission rather than
  /// for the role.
  ///
  /// Inviting is open to every member but removing is not, and deliberately:
  /// adding someone is reversible by the person who did it, while removing cuts
  /// off a colleague's access to a grid they may be mid-task on. Different blast
  /// radius, different rule.
  ///
  /// It gates the **whole trailing column**, not just the Remove row: a role
  /// somebody cannot change is not a control, and a column of identical
  /// unclickable words beside the addresses is noise in front of the thing the
  /// list is for. The owner sees roles because the owner can set them.
  final bool canRemove;

  /// The signed-in address, so one row can say "(you)". Null when unknown,
  /// which prints no marker rather than guessing at one.
  final String? viewerEmail;

  /// Where a refused write goes. The dialog owns the one place a message is
  /// shown, so two failures in a row replace each other instead of stacking.
  final ValueChanged<String> onFailure;

  /// The tallest the list draws before it scrolls inside itself. A grid can
  /// hold hundreds of people; a dialog that grows with them runs off the
  /// screen, and the access rule below would go with it.
  ///
  /// This is the one part of the dialog that scrolls — the sheet around it
  /// deliberately doesn't — so on a short window it gives way first, down to
  /// [minHeight]. Two rows is enough to read as a list; below that it would be
  /// a scroll bar with nothing beside it.
  static const double maxHeight = 224;
  static const double minHeight = 96;

  /// [maxHeight], or a quarter of a short window — whichever is smaller.
  static double capFor(BuildContext context) {
    final quarter = MediaQuery.sizeOf(context).height * 0.25;
    return quarter.clamp(minHeight, maxHeight);
  }

  Future<void> _remove(ManagedNetworkMember member) async {
    final error = await controller.remove(member.email);
    if (error != null) onFailure(error);
  }

  /// Changes what someone may do, through the endpoint the invite already
  /// uses — one POST, which is the whole change. See [GridApiClient.addMember].
  ///
  /// No confirm. Unlike removal this is reversible from the same menu in one
  /// click, and the person's client refreshes its token in place.
  Future<void> _changeRole(
    ManagedNetworkMember member,
    ManagedMemberRole role,
  ) async {
    final error = await controller.invite(email: member.email, role: role);
    if (error != null) onFailure(error);
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final people = controller.members;
    if (people == null) {
      // Two different reasons for an absent list, and they read differently:
      // still coming is rows in waiting, refused is the sentence saying so.
      if (controller.loadError case final message?) return _Note(text: message);
      return const _PeopleSkeleton();
    }
    if (people.isEmpty) return const _Note(text: 'Only you, for now.');
    return _People(
      people: people,
      me: viewerEmail?.toLowerCase(),
      canRemove: canRemove,
      grantable: grantable,
      busy: controller.busy,
      onRemove: _remove,
      onRoleChanged: _changeRole,
    );
  }
}

/// The rows themselves, once there is a roster to draw.
///
/// Split out so the colour assignment — which is a fact about the whole list,
/// see [memberAvatarSlots] — has somewhere to be computed once per build
/// instead of inside the item builder, where it would be redone for every row
/// and could not see the rows around it anyway.
class _People extends StatelessWidget {
  const _People({
    required this.people,
    required this.me,
    required this.canRemove,
    required this.grantable,
    required this.busy,
    required this.onRemove,
    required this.onRoleChanged,
  });

  final List<ManagedNetworkMember> people;
  final String? me;
  final bool canRemove;
  final List<ManagedMemberRole> grantable;
  final Set<String> busy;
  final ValueChanged<ManagedNetworkMember> onRemove;
  final void Function(ManagedNetworkMember, ManagedMemberRole) onRoleChanged;

  @override
  Widget build(BuildContext context) {
    final slots = memberAvatarSlots([
      for (final person in people) person.email,
    ], AppPalette.avatarPalette.length);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: SharePeopleList.capFor(context)),
      // Shrink-wraps until it hits the cap, so three people don't sit in a box
      // sized for ten.
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: people.length,
        itemBuilder: (context, i) => _PersonRow(
          member: people[i],
          slot: slots[i],
          isYou: people[i].email.toLowerCase() == me,
          canRemove: canRemove,
          grantable: grantable,
          busy: busy.contains(people[i].email),
          onRemove: () => onRemove(people[i]),
          onRoleChanged: (role) => onRoleChanged(people[i], role),
        ),
      ),
    );
  }
}

/// One person: who they are on the left, what they may do on the right.
///
/// Two lines where there is something true for the second one, the way Drive's
/// rows carry a name over an address — Grid has no name to print, so the line
/// below the address says whether this person has actually joined yet.
class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.member,
    required this.slot,
    required this.isYou,
    required this.canRemove,
    required this.grantable,
    required this.busy,
    required this.onRemove,
    required this.onRoleChanged,
  });

  final ManagedNetworkMember member;

  /// Which colour this person's circle takes — decided for the whole list by
  /// [memberAvatarSlots], so two rows next to each other never match.
  final int slot;

  final bool isYou;
  final bool canRemove;
  final List<ManagedMemberRole> grantable;
  final bool busy;
  final VoidCallback onRemove;
  final ValueChanged<ManagedMemberRole> onRoleChanged;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final email = member.email;
    final second = memberStatusLine(member);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          MemberAvatar(email: email, slot: slot, size: 32, fontSize: 13),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Address(email: email, isYou: isYou),
                if (second != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    second,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppPalette.textSecondary,
                      fontSize: 12.5,
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          _Trailing(
            member: member,
            canRemove: canRemove,
            grantable: grantable,
            busy: busy,
            onRemove: onRemove,
            onRoleChanged: onRoleChanged,
          ),
        ],
      ),
    );
  }
}

/// The address, cut the way the rail's members panel cuts it: the part that
/// differs in full ink, the domain everyone shares behind it in a lighter one.
class _Address extends StatelessWidget {
  const _Address({required this.email, required this.isYou});

  final String email;
  final bool isYou;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: memberLocalPart(email),
            style: TextStyle(
              color: AppPalette.textPrimary,
              fontWeight: AppFont.semibold,
            ),
          ),
          TextSpan(
            text: memberDomainPart(email),
            style: TextStyle(color: AppPalette.textSecondary),
          ),
          if (isYou)
            TextSpan(
              text: ' (you)',
              style: TextStyle(color: AppPalette.textSecondary),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 13, height: 1.25),
    );
  }
}

/// What this row can say, and what it can do: a spinner mid-write, the owner's
/// badge, or the role with its menu.
class _Trailing extends StatelessWidget {
  const _Trailing({
    required this.member,
    required this.canRemove,
    required this.grantable,
    required this.busy,
    required this.onRemove,
    required this.onRoleChanged,
  });

  final ManagedNetworkMember member;
  final bool canRemove;
  final List<ManagedMemberRole> grantable;
  final bool busy;
  final VoidCallback onRemove;
  final ValueChanged<ManagedMemberRole> onRoleChanged;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    if (busy) {
      return const Padding(
        padding: EdgeInsets.all(6),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    // The owner is a permanent member — the control plane won't remove them, so
    // they get a word rather than a control that can't work.
    if (member.isOwner) {
      return Padding(
        padding: const EdgeInsets.only(right: 7),
        child: Text(
          'Owner',
          style: TextStyle(color: AppPalette.textFaint, fontSize: 13),
        ),
      );
    }
    // Nothing at all on the rows where the column could only repeat itself.
    //
    // Someone admitted by their email domain holds the grant the RULE hands
    // out — every one of them the same `both`, synthesised by the control plane
    // with no row to remove and no grant to change. On the live autonomous.ai
    // grid that would print "Share a computer" down twenty rows, saying nothing
    // "Who can join" hadn't already said once. And a viewer who does not own the
    // grid can act on none of it: ranking the people already here is the
    // owner's business, so for everyone else the column was a wall of
    // unclickable text beside the names they came to read.
    if (member.isDomainMember || !canRemove) return const SizedBox.shrink();
    return GridRoleMenu(
      role: member.grantedRole,
      roles: grantable,
      alignEnd: true,
      tooltip: 'Access options',
      onRoleChanged: onRoleChanged,
      onRemove: onRemove,
    );
  }
}

/// The list before it arrives: rows in the shape they'll land in.
///
/// A sentence ("Loading people…") made the dialog jump — the line is one row
/// tall, so the access rule below it leapt down the moment the members arrived.
/// Rows that already occupy the space don't, which is the whole point of a
/// skeleton over a spinner.
///
/// Three rows: this block is capped at [SharePeopleList.capFor] anyway, and a
/// skeleton taller than the list it stands in for causes the jump it exists to
/// prevent — upward, which is worse.
class _PeopleSkeleton extends StatelessWidget {
  const _PeopleSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Fading down the column so the block reads as "more below" rather than
        // as a wall that stops at an arbitrary row.
        Opacity(opacity: 1, child: _PeopleSkeletonRow()),
        Opacity(opacity: 0.78, child: _PeopleSkeletonRow()),
        Opacity(opacity: 0.56, child: _PeopleSkeletonRow()),
      ],
    );
  }
}

/// One placeholder row, padded like the real one.
class _PeopleSkeletonRow extends StatelessWidget {
  const _PeopleSkeletonRow();

  @override
  Widget build(BuildContext context) {
    return const SkeletonListTile(
      // Most rows are one line — the address. The second line only appears for
      // someone who hasn't joined yet, which is the exception.
      subtitle: false,
      padding: EdgeInsets.symmetric(vertical: 7),
    );
  }
}

/// Empty and error read as one calm line rather than two differently-shaped
/// blocks — the list is a paragraph of the dialog, not a screen of its own.
class _Note extends StatelessWidget {
  const _Note({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        text,
        style: TextStyle(
          color: AppPalette.textSecondary,
          fontSize: 13,
          height: 1.35,
        ),
      ),
    );
  }
}
