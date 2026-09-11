import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../shared/theme/app_theme.dart';

/// The pieces a phone settings list is built from — the grouped inset list every phone OS uses,
/// rather than the desktop's `SettingRow` (a raised block with a fixed-width control on the right,
/// sized for a pane that is never narrower than a sidebar allows).
///
/// The height every settings row clears.
///
/// Set by the tallest control a row can carry — the stepper, at 34pt — plus 8pt of breathing room
/// above and below it. A row with only text is padded up to the same, so a group reads as evenly
/// spaced rather than as rows of two different sizes.
const double kSettingsRowHeight = 50;

/// How far a chevron's arrow stops short of the right edge of its own box.
///
/// MEASURED, not eyeballed: in `lucide.ttf` the `chevron-right` outline runs from 334 to 666 across
/// a 1000-unit advance, so at the 20pt this row draws it the arrow carries 6.68pt of blank on either
/// side. A chevron laid flush against the row's 13pt padding therefore LOOKS inset by nearly 20,
/// while "1.0.0" on the About row below — plain text, no built-in margin — really does end at 13.
/// One padding value, two different right edges: the ragged margin the Font and Version rows showed.
/// Cancelling the glyph's own blank puts the arrow where the text ends, which is where the eye reads
/// the card's edge to be.
///
/// Re-measure if the icon size or the icon pack changes; this number belongs to both.
const double _chevronInk = 6.68;

/// A caption over a run of rows.
class SettingsCaption extends StatelessWidget {
  const SettingsCaption(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Padding(
      // 22 above, 8 below: the caption belongs to the group under it, so it sits much closer to
      // that group than to the one it follows. Equal gaps either side would leave every caption
      // floating between two cards with nothing to say which it labels.
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: AppPalette.textFaint,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// A quiet sentence under a run, explaining something the rows cannot say themselves.
class SettingsNote extends StatelessWidget {
  const SettingsNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Padding(
      // 10 rather than 8, and the extra 2 is doing work: the caption above a group sits at 8, so a
      // note at the same gap reads as another caption for whatever follows rather than as a remark
      // on the group it belongs to.
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
      child: Text(
        text,
        style: TextStyle(
          color: AppPalette.textFaint,
          fontSize: 12.5,
          height: 1.45,
        ),
      ),
    );
  }
}

/// One run of rows, drawn as a single card with hairlines between them.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Container(
      // Full width, so a card is as wide as the list lets it be rather than as wide as its widest
      // row happens to need. Belt and braces with the `stretch` below: the alignment makes the rows
      // fill the card, this makes the card fill the list.
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppGlass.rowFill,
        borderRadius: BorderRadius.circular(AppCard.radius),
        border: Border.all(color: AppGlass.hair),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppCard.radius),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          // ⚠️ `stretch`, not the `center` default — this is what makes every card the same width.
          //
          // A Column sizes itself to its WIDEST child and then centres the narrower ones inside
          // that. A group whose rows are all text (Font, Version) has no wide child to stretch it,
          // so its card came out narrower than one holding a stepper — and since the list centres
          // the cards, the difference showed up as a short right edge on some groups and not
          // others. Stretching makes every row take the full width the list gives the card, so all
          // the cards end on one line whatever is inside them.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: AppGlass.hair),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// One row: a title, an optional detail line, and either a value with a chevron (it opens
/// something) or a [trailing] control (it changes something in place).
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.detail,
    this.value,
    this.leading,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  final String title;
  final String? detail;

  /// The current setting, shown at the right. Paired with [onTap] it gets a chevron.
  final String? value;

  final Widget? leading;

  /// A control that changes the setting without leaving the page — a stepper. Mutually exclusive
  /// with [value] in practice; if both are given, this wins and no chevron is drawn.
  final Widget? trailing;

  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final titleColor = destructive
        ? AppPalette.dangerFill
        : AppPalette.textPrimary;
    final row = Container(
      // A floor rather than a fixed height, so a row with a two-line detail still grows. Every row
      // in a group clears the same bar — without it a row carrying a stepper (34pt tall) stands
      // visibly taller than one carrying only a value, and a group of four reads as ragged.
      constraints: const BoxConstraints(minHeight: kSettingsRowHeight),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    detail!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppPalette.textSecondary,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Everything on the right sits in one run, so a value + chevron and a stepper end on the
          // same margin. Previously the value was a bare `Flexible` between two other children,
          // which let it settle wherever the title's `Expanded` left it — "SF Mono ›" floated in
          // from the edge while the stepper below it stayed flush, and the card's right margin
          // read as two different margins.
          if (trailing != null)
            trailing!
          else if (value != null || onTap != null)
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (value != null)
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: Text(
                          value!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            color: AppPalette.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  if (onTap != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Transform.translate(
                        // Nudged right by the blank the glyph brings with it — see [_chevronInk].
                        // Translate rather than a negative right padding, which `EdgeInsets`
                        // rejects: this has to move the ink WITHOUT giving the row a wider
                        // trailing box, or the chevron would simply take its padding back.
                        offset: const Offset(_chevronInk, 0),
                        child: Icon(
                          LucideIcons.chevronRight300,
                          size: 20,
                          color: AppPalette.textFaint,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: row),
    );
  }
}

/// − value + in a recessed well. A null callback greys its side out, so a control at its limit
/// says so instead of answering a tap by doing nothing.
class SettingsStepper extends StatelessWidget {
  const SettingsStepper({
    super.key,
    required this.value,
    this.onDecrease,
    this.onIncrease,
  });

  final String value;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppSurface.recess,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepButton(
            icon: LucideIcons.minus300,
            tooltip: 'Smaller',
            onPressed: onDecrease,
          ),
          SizedBox(
            width: 34,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppPalette.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                fontFeatures: AppFont.tabularFigures,
              ),
            ),
          ),
          _StepButton(
            icon: LucideIcons.plus300,
            tooltip: 'Larger',
            onPressed: onIncrease,
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 36,
            height: 34,
            child: Icon(
              icon,
              size: 17,
              color: onPressed == null
                  ? AppPalette.textFaint
                  : AppPalette.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
