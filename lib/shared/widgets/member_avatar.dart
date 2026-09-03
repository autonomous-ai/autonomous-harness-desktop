import 'package:flutter/material.dart';

import '../../grid/member_display.dart' show memberInitial;
import '../theme/app_theme.dart';

/// A member's circle: their initial, on one of the roster's colours.
///
/// Copied from Grid (`shared/widgets/member_avatar.dart`), so a face is the
/// same shape and weight wherever it appears — the rail's members panel and the
/// share sheet's people list — and only its size changes with the room it is in.
///
/// Grid's own version grows a ring for a stack where the discs overlap; nothing
/// in this app stacks them, so that half is left where it came from rather than
/// carried over unused.
///
/// It does not pick the colour. [memberAvatarSlots] does, over the whole list at
/// once, because the property worth having is that no two circles *near each
/// other* match — and that is not a question a single circle can answer.
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({
    super.key,
    required this.email,
    required this.slot,
    required this.size,
    required this.fontSize,
  });

  /// The address the letter is taken from — never what the circle prints
  /// beside it, which is the row's business.
  final String email;

  /// Which of [AppPalette.avatarPalette] to fill with, from
  /// `memberAvatarSlots` over the whole list this circle belongs to. Passed in
  /// rather than hashed here because "is this colour already used two rows up?"
  /// is a question only the list can answer.
  final int slot;

  final double size;

  /// Set per call site rather than derived from [size]: a 22px circle in a
  /// 13pt row and a 32px one in a dialog want different optical weights, and a
  /// ratio that suits one leaves the other's glyph too small or too crowded.
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final palette = AppPalette.avatarPalette;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: palette[slot % palette.length],
      ),
      // A step heavier than the text beside it: white on a saturated fill reads
      // thinner than the same weight on a flat surface.
      child: Text(
        memberInitial(email),
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}
