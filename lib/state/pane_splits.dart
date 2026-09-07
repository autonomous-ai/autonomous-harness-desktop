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
  const PaneSplits({this.row = 0.5, this.col = 0.5});

  /// The top row's share of the height. Used by the 3- and 4-pane layouts.
  final double row;

  /// The vertical divider, shared by every row.
  ///
  /// ONE line down the whole grid, not one per row. The rows were briefly
  /// independent and it was wrong in the hand: dragging the boundary between
  /// two tiles left the one directly below it behind, so the grid came apart
  /// into a staircase and the second drag existed only to repair the first.
  /// A column is a column.
  final double col;

  /// Never let a divider be dragged onto the edge. The real floor is a
  /// terminal's 40-column minimum and is applied in pixels where the width is
  /// known; this is the coarse backstop that keeps a stored file from
  /// producing a zero-width tile before any of that is measured.
  static const double minFraction = 0.15;
  static const double maxFraction = 0.85;

  static double _clamp(double v) =>
      v.isFinite ? v.clamp(minFraction, maxFraction) : 0.5;

  PaneSplits copyWith({double? row, double? col}) => PaneSplits(
    row: _clamp(row ?? this.row),
    col: _clamp(col ?? this.col),
  );

  bool get isDefault => row == 0.5 && col == 0.5;

  Map<String, dynamic> toJson() => {'row': row, 'col': col};

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
      // `colTop` is what the one release with per-row columns wrote. Read it so
      // a grid saved by that build opens where it was left rather than jumping
      // back to centre; `colBottom` is dropped, since there is nowhere left to
      // put a second column.
      col: raw.containsKey('col') ? read('col') : read('colTop'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PaneSplits && other.row == row && other.col == col;

  @override
  int get hashCode => Object.hash(row, col);
}
