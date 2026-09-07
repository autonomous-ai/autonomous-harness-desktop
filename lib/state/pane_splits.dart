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
  const PaneSplits({
    this.row = 0.5,
    this.col = 0.5,
    this.cols = const [],
    this.rows = const [],
  });

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

  /// Column widths for the UNIFORM GRID used above four panes, as fractions
  /// summing to one. Empty means even.
  ///
  /// A second model beside [row]/[col], and deliberately so. The hand-tuned
  /// shapes for one to four panes are not grids — three tiles are two over one,
  /// and that bottom tile SPANS. A per-axis list cannot say "spanning", so
  /// forcing those shapes through it would mean giving them up. Each model is
  /// read by exactly one arrangement path.
  final List<double> cols;

  /// Row heights for that same grid. Empty means even.
  final List<double> rows;

  /// Never let a divider be dragged onto the edge. The real floor is a
  /// terminal's 40-column minimum and is applied in pixels where the width is
  /// known; this is the coarse backstop that keeps a stored file from
  /// producing a zero-width tile before any of that is measured.
  static const double minFraction = 0.15;
  static const double maxFraction = 0.85;

  static double _clamp(double v) =>
      v.isFinite ? v.clamp(minFraction, maxFraction) : 0.5;

  PaneSplits copyWith({
    double? row,
    double? col,
    List<double>? cols,
    List<double>? rows,
  }) => PaneSplits(
    row: _clamp(row ?? this.row),
    col: _clamp(col ?? this.col),
    cols: _normalise(cols ?? this.cols),
    rows: _normalise(rows ?? this.rows),
  );

  bool get isDefault =>
      row == 0.5 && col == 0.5 && cols.isEmpty && rows.isEmpty;

  Map<String, dynamic> toJson() => {
    'row': row,
    'col': col,
    if (cols.isNotEmpty) 'cols': cols,
    if (rows.isNotEmpty) 'rows': rows,
  };

  /// Fractions that sum to one, with none small enough to be unusable.
  ///
  /// Stored normalised rather than normalised on read: a list that has to be
  /// repaired every time it is drawn is a list that will eventually be drawn
  /// before someone remembers to repair it.
  static List<double> _normalise(List<double> value) {
    if (value.length < 2) return const [];
    final safe = [for (final v in value) v.isFinite && v > 0 ? v : minFraction];
    final total = safe.reduce((a, b) => a + b);
    if (total <= 0) return const [];
    return [for (final v in safe) v / total];
  }

  /// Even fractions for `n` slots — what an untouched axis looks like.
  static List<double> even(int n) =>
      n < 2 ? const [] : List<double>.filled(n, 1 / n);

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
      cols: _readList(raw['cols']),
      rows: _readList(raw['rows']),
    );
  }

  static List<double> _readList(Object? raw) {
    if (raw is! List) return const [];
    final out = <double>[];
    for (final item in raw) {
      if (item is! num || !item.isFinite || item <= 0) return const [];
      out.add(item.toDouble());
    }
    return _normalise(out);
  }

  @override
  bool operator ==(Object other) =>
      other is PaneSplits &&
      other.row == row &&
      other.col == col &&
      _same(other.cols, cols) &&
      _same(other.rows, rows);

  static bool _same(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(row, col, Object.hashAll(cols), Object.hashAll(rows));
}
