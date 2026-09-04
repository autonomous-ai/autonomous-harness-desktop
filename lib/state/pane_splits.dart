/// Where the dividers sit in a pane arrangement, as fractions of what they split.
///
/// Fractions, not pixels, and that distinction is the reason these can be
/// remembered at all: [PaneLayoutStore] deliberately refuses to store sizes
/// because "sizes … would be lies by the next one" — true of `740px`, which
/// means something different on another display, and not true of `0.62`, which
/// means the same thing on any of them.
///
/// One set per pane COUNT. The arrangements are different shapes, so a divider
/// in the 3-pane layout is not the same divider as in the 4-pane one, and
/// carrying a fraction across would move a boundary the user never touched.
class PaneSplits {
  const PaneSplits({this.row = 0.5, this.colTop = 0.5, this.colBottom = 0.5});

  /// The top row's share of the height. Used by the 3- and 4-pane layouts.
  final double row;

  /// The first row's vertical divider. This is the only one a 2-pane layout
  /// has, whichever way it happens to be split.
  final double colTop;

  /// The second row's vertical divider — 4 panes only. Independent of
  /// [colTop] by choice: two rows that must share one column line make the
  /// wider tile in each row fight over the same number.
  final double colBottom;

  /// Never let a divider be dragged onto the edge. The real floor is a
  /// terminal's 40-column minimum and is applied in pixels where the width is
  /// known; this is the coarse backstop that keeps a stored file from
  /// producing a zero-width tile before any of that is measured.
  static const double minFraction = 0.15;
  static const double maxFraction = 0.85;

  static double _clamp(double v) =>
      v.isFinite ? v.clamp(minFraction, maxFraction) : 0.5;

  PaneSplits copyWith({double? row, double? colTop, double? colBottom}) =>
      PaneSplits(
        row: _clamp(row ?? this.row),
        colTop: _clamp(colTop ?? this.colTop),
        colBottom: _clamp(colBottom ?? this.colBottom),
      );

  bool get isDefault => row == 0.5 && colTop == 0.5 && colBottom == 0.5;

  Map<String, dynamic> toJson() => {
    'row': row,
    'colTop': colTop,
    'colBottom': colBottom,
  };

  /// Anything unreadable falls back to centred. A hand-edited or
  /// future-written file is a reason to open the grid the way a new user sees
  /// it, not a reason to refuse to lay out.
  static PaneSplits fromJson(Object? raw) {
    if (raw is! Map) return const PaneSplits();
    double read(String key) {
      final value = raw[key];
      return value is num ? _clamp(value.toDouble()) : 0.5;
    }

    return PaneSplits(
      row: read('row'),
      colTop: read('colTop'),
      colBottom: read('colBottom'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PaneSplits &&
      other.row == row &&
      other.colTop == colTop &&
      other.colBottom == colBottom;

  @override
  int get hashCode => Object.hash(row, colTop, colBottom);
}
