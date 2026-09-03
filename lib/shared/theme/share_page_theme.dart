import 'package:flutter/material.dart';

import 'app_theme.dart';

/// The Share Intelligence mockup's own palette and type, to the value.
///
/// Copied from Grid's `shared/theme/share_page_theme.dart`, like the rest of
/// `lib/shared/` — the page it dresses was designed once and now exists in both
/// apps, and a token nudged in one of them is a screenshot that no longer
/// matches the other. Keep the two in step.
///
/// A second palette in one app is a drift risk (§5), and this one is here on
/// purpose: the design for that page is a *cooler* family than [AppPalette] —
/// blue-grey inks at hue 265 where the app runs warm at `#62615B`, a deeper
/// accent, and hairlines several shades darker than the app's 6% black, which
/// on white is nearly invisible. Matching it by nudging [AppPalette] would
/// restyle every screen in the app; matching it here restyles the page that was
/// designed.
///
/// **TODO(BE): four of these inks are under §11's 4.5:1 floor**, measured on
/// this page's own two grounds (`#F9FAFB` rail / `#FDFDFF` card):
///
/// ```
///   line    #74777F   4.29 / 4.41    route card description, 12.3px
///   note    #777A82   4.11 / 4.23    status note, field helper, 12px
///   helper  #7D8088   3.78 / 3.89    footnote and button helper, 11.5–12.5px
///   eyebrow #83868E   3.49 / 3.59    CHOOSE A ROUTE, ROUTE 01, 10.5px
/// ```
///
/// They are the mockup's values and they ship because the mockup is the brief.
/// The floor is not negotiable long-term: darkening each by roughly one step
/// (0.55/0.55/0.55/0.5 lightness) clears it and is invisible beside the
/// original. Decide it, don't inherit it.
///
/// Dark values are *derived*, not designed — the mockup is light-only. Each one
/// answers "what plays this role on a dark ground", taken from [AppPalette] so
/// the page stays coherent in a theme the design never covered.
abstract final class SharePalette {
  /// The ground the whole page sits on.
  static Color get pageBg =>
      AppTheme.pick(const Color(0xFFF6F7F9), const Color(0xFF181818));

  /// The rail, a shade above the page so the split reads without a heavy rule.
  static Color get railBg =>
      AppTheme.pick(const Color(0xFFF9FAFB), const Color(0xFF141414));

  /// Cards, plates and the status block.
  static Color get surface =>
      AppTheme.pick(const Color(0xFFFDFDFF), const Color(0xFF1E1E1E));

  /// The hairline round a card and down the middle of the page.
  static Color get rim =>
      AppTheme.pick(const Color(0xFFE1E3E6), const Color(0xFF2E2E2E));

  /// The rule *inside* a plate, one shade lighter than its own rim.
  static Color get innerRule =>
      AppTheme.pick(const Color(0xFFE8E9ED), const Color(0xFF282828));

  /// The rule above the rail's footnote.
  static Color get footRule =>
      AppTheme.pick(const Color(0xFFE4E6EA), const Color(0xFF2A2A2A));

  /// The unfilled half of a slider's track. A shade under [rim]: the track is
  /// a surface the thumb runs over, not an edge round a card.
  static Color get track =>
      AppTheme.pick(const Color(0xFFE0E1E5), const Color(0xFF313131));

  /// A field's own rim and fill — visible at rest, unlike the app's borderless
  /// capsule.
  static Color get fieldRim =>
      AppTheme.pick(const Color(0xFFDCDEE1), const Color(0xFF343434));
  static Color get fieldFill =>
      AppTheme.pick(const Color(0xFFF9FAFB), const Color(0xFF262626));

  /// A control under the pointer. One step, not a colour change — the field is
  /// telling you it can be used, not that anything has happened yet.
  static Color get fieldFillHover =>
      AppTheme.pick(const Color(0xFFF2F4F7), const Color(0xFF2C2C2C));
  static Color get fieldRimHover =>
      AppTheme.pick(const Color(0xFFCBCDD2), const Color(0xFF454545));

  /// The focused control's rim, and the soft ring outside it.
  ///
  /// macOS rings the focused control in the accent and this page had no focus
  /// state at all: every field looked identical whether or not the keyboard was
  /// pointed at it, which on a pane of six boxes is a real question the screen
  /// refused to answer.
  static Color get fieldRimFocus => accent;
  static Color get fieldRingFocus => accent.withValues(alpha: 0.22);

  /// A menu row under the pointer, and the wash on the row that is the current
  /// choice. The same recipe as the app's own menu, in this page's palette.
  static Color get hoverFill =>
      AppTheme.pick(const Color(0xFFEFF1F5), const Color(0xFF2A2A2A));
  static Color get selectedFill =>
      AppTheme.pick(const Color(0xFFEBF0FB), const Color(0xFF232A38));

  /// Headings and anything the reader is meant to read first.
  static Color get ink =>
      AppTheme.pick(const Color(0xFF1C1F25), const Color(0xFFF5F5F5));

  /// A field's label.
  static Color get labelInk =>
      AppTheme.pick(const Color(0xFF4A4D54), const Color(0xFFC9C9C9));

  /// Body copy: the rail's subtitle, a pane's paragraph.
  static Color get body =>
      AppTheme.pick(const Color(0xFF6E7279), const Color(0xFFA8A8A2));

  /// A route card's description.
  static Color get line =>
      AppTheme.pick(const Color(0xFF74777F), const Color(0xFF9E9E9A));

  /// A note under a control, and the sharing status' second line.
  static Color get note =>
      AppTheme.pick(const Color(0xFF777A82), const Color(0xFF9A9A96));

  /// The quiet line beside a button, and the rail's footnote.
  static Color get helper =>
      AppTheme.pick(const Color(0xFF7D8088), const Color(0xFF949490));

  /// Capitalised section labels, and a slider's end marks.
  static Color get eyebrow =>
      AppTheme.pick(const Color(0xFF83868E), const Color(0xFF8C8C88));

  /// The one blue on the page: a selected route, a link, the button that
  /// finishes the job.
  static Color get accent =>
      AppTheme.pick(const Color(0xFF2261DD), const Color(0xFF4C82F0));
  static Color get accentHover =>
      AppTheme.pick(const Color(0xFF0E4EC8), const Color(0xFF6C99F4));

  /// The halo under a slider's thumb while it is being dragged.
  ///
  /// It used to be the ring round a selected route card, a sort chip and a
  /// selected repo row as well — which spent the accent on four different
  /// *states* while the button that acts is the only thing that should be
  /// wearing it. Selection is [selectedFill] and a rim now; this is left to the
  /// one place where the accent really is following the pointer.
  static Color get accentRing => accent.withValues(alpha: 0.14);

  /// Live: the dot, and the eyebrow over the live pane.
  static Color get liveDot =>
      AppTheme.pick(const Color(0xFF269E5F), const Color(0xFF3FB950));
  static Color get liveInk =>
      AppTheme.pick(const Color(0xFF007840), const Color(0xFF3FB950));

  /// Idle: the dot when nothing is reachable.
  static Color get idleDot =>
      AppTheme.pick(const Color(0xFFA8AEBB), const Color(0xFF6E6E6E));

  /// A refusal: the ink of "this did not start", and the ground under it.
  ///
  /// Not in the Grid mockup, which drew no failure — and not [AppPalette]'s
  /// `dangerFill` either, which is a fill for white text: on this page's dark
  /// card that red measures 2.9:1 as ink, well under §11's floor. Derived the
  /// way every other dark value here is, and measured on the grounds it is
  /// actually used on: 5.5:1 light, 5.4:1 dark.
  static Color get danger =>
      AppTheme.pick(const Color(0xFFB3261E), const Color(0xFFFF6B63));

  static Color get dangerSoft => danger.withValues(alpha: 0.10);

  /// A quiet chip: today the context window's value. It was the route cards'
  /// benefit badge too, until those went.
  static Color get badgeFill =>
      AppTheme.pick(const Color(0xFFEDF0F6), const Color(0xFF2A2A2A));

  /// Ink for something the reader cannot act on yet: a step that has not opened,
  /// a model chip switched off. Quieter than [note] on purpose — the point is
  /// that it recedes — but still measured against the page's grounds rather
  /// than faded with an alpha, which is how a "disabled" colour usually ends up
  /// unreadable.
  static Color get dim =>
      AppTheme.pick(const Color(0xFF8A8D95), const Color(0xFF7A7A76));

  /// A finished step's pip: the ring the tick sits in.
  static Color get stepDoneFill =>
      AppTheme.pick(const Color(0xFFE6F4EC), const Color(0xFF1D3A26));
  static Color get stepDoneRim =>
      AppTheme.pick(const Color(0xFFB6DCC6), const Color(0xFF2C5B39));

  /// The line joining one step's pip to the next.
  static Color get stepStem =>
      AppTheme.pick(const Color(0xFFE1E3E6), const Color(0xFF2A2A2A));

  /// A chosen option in a list of them — the engine this share will point at.
  ///
  /// Barely a tint. The first attempt washed the whole card blue, which put a
  /// coloured ground under fields whose own fill is a neutral grey — two
  /// temperatures in one box — and gave a *selected* thing more weight than the
  /// button that acts on it. The rim and the filled radio carry the state; the
  /// fill only lifts the card off the page.
  static Color get optionFill =>
      AppTheme.pick(const Color(0xFFFAFBFD), const Color(0xFF202225));
  static Color get optionRim =>
      AppTheme.pick(const Color(0xFFC8D5EC), const Color(0xFF3C444F));

  /// A state tag on an option: Ollama, stopped.
  static Color get tagFill =>
      AppTheme.pick(const Color(0xFFFBF0DC), const Color(0xFF33291A));
  static Color get tagInk =>
      AppTheme.pick(const Color(0xFF8A5A12), const Color(0xFFD2A24C));
}

/// The mockup's type scale, by the role each size plays rather than by number.
///
/// Sizes and letter-spacing are the design's own. They do not come from
/// [TextTheme] because the app's scale is a different one — matching the mockup
/// means saying what it says.
abstract final class ShareType {
  /// The rail's headline: "Put this computer to work."
  static TextStyle get railTitle => TextStyle(
    fontSize: 27,
    height: 1.12,
    fontWeight: AppFont.semibold,
    letterSpacing: -0.028 * 27,
    color: SharePalette.ink,
  );

  /// The rail's paragraph under it.
  static TextStyle get railBody =>
      TextStyle(fontSize: 13.5, height: 1.5, color: SharePalette.body);

  /// A pane's headline: "Run a model on this computer."
  static TextStyle get paneTitle => TextStyle(
    fontSize: 22,
    fontWeight: AppFont.semibold,
    letterSpacing: -0.022 * 22,
    color: SharePalette.ink,
  );

  /// A pane's paragraph.
  static TextStyle get paneBody =>
      TextStyle(fontSize: 13.5, height: 1.55, color: SharePalette.body);

  /// A step's title. Between the pane's headline and a card's — a step is a
  /// heading inside the page, not a second page title, and its line height is
  /// pinned to the pip beside it so the two share a baseline.
  static TextStyle get stepTitle => TextStyle(
    fontSize: 15,
    height: ShareMetrics.pipSize / 15,
    fontWeight: AppFont.semibold,
    letterSpacing: -0.012 * 15,
    color: SharePalette.ink,
  );

  /// CHOOSE A ROUTE · ROUTE 01 · LIVE ON THE GRID.
  static TextStyle get eyebrow => TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.1 * 10.5,
    color: SharePalette.eyebrow,
  );

  /// A route card's title, and the status block's.
  static TextStyle get cardTitle => TextStyle(
    fontSize: 13.5,
    fontWeight: AppFont.semibold,
    letterSpacing: -0.01 * 13.5,
    color: SharePalette.ink,
  );

  /// A route card's description.
  static TextStyle get cardLine =>
      TextStyle(fontSize: 12.3, height: 1.45, color: SharePalette.line);

  /// What a route costs, under its description. Tabular so the figures on
  /// three stacked cards line up rather than wander.
  static TextStyle get cost => TextStyle(
    fontSize: 10.5,
    height: 1.35,
    color: SharePalette.eyebrow,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// The sharing status' title.
  static TextStyle get statusTitle => TextStyle(
    fontSize: 12.5,
    fontWeight: AppFont.semibold,
    color: SharePalette.ink,
  );

  /// The sharing status' second line, and a helper under a field.
  static TextStyle get note =>
      TextStyle(fontSize: 12, height: 1.45, color: SharePalette.note);

  /// The rail's closing note.
  static TextStyle get footnote =>
      TextStyle(fontSize: 11.5, height: 1.5, color: SharePalette.helper);

  /// The line that sits beside a button.
  static TextStyle get buttonHelper =>
      TextStyle(fontSize: 12.5, color: SharePalette.helper);

  /// A field's label.
  static TextStyle get fieldLabel => TextStyle(
    fontSize: 12,
    fontWeight: AppFont.semibold,
    color: SharePalette.labelInk,
  );

  /// What a control holds: typed text, the chosen row of a picker. One style,
  /// so a name box and the select beside it sit on the same line at the same
  /// size — which they did not, because each form set its own.
  static TextStyle get fieldValue =>
      TextStyle(fontSize: 13.5, height: 1.2, color: SharePalette.ink);

  /// What a control shows when it holds nothing yet. [helper], not [note]:
  /// a placeholder is not information, and reading as though it were is how a
  /// hint gets mistaken for a value.
  static TextStyle get fieldPlaceholder =>
      fieldValue.copyWith(color: SharePalette.helper);

  /// A row inside a picker's panel.
  static TextStyle get menuRow =>
      TextStyle(fontSize: 13, height: 1.25, color: SharePalette.ink);

  /// A badge: a model's size, a context window's value. Tabular, because these
  /// are figures stacked down a menu and compared against each other.
  static TextStyle get badge => TextStyle(
    fontSize: 11,
    fontWeight: AppFont.semibold,
    height: 1.2,
    color: SharePalette.labelInk,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// A state tag on an option — Ollama, STOPPED.
  static TextStyle get tag => TextStyle(
    fontSize: 9.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.07 * 9.5,
    height: 1.2,
    color: SharePalette.tagInk,
  );

  /// What every button on this page says, at the one size they all are.
  static TextStyle get button =>
      TextStyle(fontSize: 13, fontWeight: AppFont.semibold, height: 1.2);

  /// The two ends of a scale. [eyebrow]'s size, but without its tracking —
  /// letter-spacing belongs to a capitalised label, and these are readings.
  static TextStyle get scaleEnd => TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: SharePalette.eyebrow,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

/// The mockup's metrics. Named so a number is written once and read where it is
/// used, rather than typed into six widgets that then drift apart.
abstract final class ShareMetrics {
  static const double railWidth = 396;
  static const EdgeInsets railPadding = EdgeInsets.fromLTRB(28, 34, 28, 28);
  static const EdgeInsets panePadding = EdgeInsets.fromLTRB(40, 34, 40, 40);

  /// Between the rail's blocks, and between a pane's.
  static const double railGap = 26;
  static const double paneGap = 24;

  /// Card radii: the plate, a route card, the status block, a field, a badge.
  static const double plateRadius = 13;
  static const double cardRadius = 11;
  static const double statusRadius = 10;
  static const double fieldRadius = 9;
  static const double badgeRadius = 5;

  /// A plate's own sections.
  static const EdgeInsets plateSection = EdgeInsets.fromLTRB(20, 18, 20, 18);

  /// Every control on this page is this tall: a field, a select, a button. One
  /// number, because a 36px button beside a 38px field is the kind of half-step
  /// nobody can name and everybody can see.
  static const double controlHeight = 38;

  /// The second size, for a control that sits inside a row of content rather
  /// than at the end of a form — the Download beside a recommended model.
  static const double controlHeightSmall = 30;

  /// A button, and the gap to the line beside it.
  static const double buttonHeight = controlHeight;
  static const double buttonGap = 14;

  /// A menu's row height and the radius of its hover pill, and the panel's own
  /// padding. Taken from the app's menu recipe so a picker on this page behaves
  /// like every other picker in the app, in this page's palette.
  static const double menuRowExtent = 34;
  static const double menuRowRadius = 7;
  static const EdgeInsets menuPadding = EdgeInsets.symmetric(vertical: 5);

  /// A panel is never narrower than the control it drops out of, and never so
  /// tall it runs off the window.
  static const double menuMinWidth = 260;
  static const double menuMaxHeight = 360;

  /// The stepper: the pip's diameter, the gutter its column occupies, and the
  /// gap under one step before the next one's title.
  static const double pipSize = 22;
  static const double stepGutter = 16;
  static const double stepGap = 24;

  /// A pane's steps never run wider than this, whatever the window does. Past
  /// it a step's paragraph stops being one thing the eye can take in, and the
  /// form under it drifts away from the title that names it.
  static const double stepMaxWidth = 680;
}
