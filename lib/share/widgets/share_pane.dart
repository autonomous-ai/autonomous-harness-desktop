import 'package:flutter/material.dart';

import '../../grid/grid_selection_store.dart';
import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/theme/share_page_theme.dart';
import 'share_skeleton.dart';
import '../grid_cli.dart';
import '../model_pull.dart';
import '../share_controller.dart';
import 'share_detail.dart';
import 'share_rail.dart';

/// Share Intelligence: the three ways in on the left, the one being set up on
/// the right.
///
/// The one settings screen that is not wrapped in `SectionScaffold`, and the
/// rail is the reason. That frame draws a page title and a rule across the top,
/// which is right when a screen is one column of content — but here the
/// heading, the machine's status and the route picker are *one thing* running
/// down the left, and a second title above them would say "Share Intelligence"
/// over a rail whose own first line already says what the page is for. The row
/// in the settings rail carries the name.
class SharePane extends StatefulWidget {
  const SharePane({super.key, this.selection, this.cli});

  /// Injected by tests. Null in the app, where the singleton is the choice the
  /// rest of the app is already showing.
  final GridSelectionStore? selection;
  final GridCli? cli;

  @override
  State<SharePane> createState() => _SharePaneState();
}

class _SharePaneState extends State<SharePane> {
  /// Below this the two panes stop being two: a 396px rail beside a form is
  /// most of a narrow pane, and both halves end up too tight to read. This is
  /// measured on the pane rather than the window — the settings rail has
  /// already taken its share before this widget sees anything.
  static const double _splitAt = 900;

  late final GridCli _cli = widget.cli ?? GridCli();
  late final ShareController _controller = ShareController(cli: _cli);
  late final ModelPullController _pull = ModelPullController(cli: _cli);
  GridSelectionStore get _selection => widget.selection ?? gridSelectionStore;

  String? _loadedFor;

  @override
  void initState() {
    super.initState();
    _selection.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _selection.removeListener(_load);
    _controller.dispose();
    _pull.dispose();
    super.dispose();
  }

  /// Probe the machine for the chosen grid, once per grid.
  ///
  /// Guarded on the id because the store notifies for a model change too, and
  /// re-running discovery — three HTTP probes and two CLI spawns — because
  /// somebody picked a different model would be work nobody asked for.
  Future<void> _load() async {
    final selection = _selection.value;
    if (!selection.hasGrid || selection.networkId == _loadedFor) return;
    _loadedFor = selection.networkId;
    // A new grid is a new question: blank the page for it.
    _probed = false;
    await _controller.refresh(selection.networkId!);
    _probed = true;
  }

  /// Whether this pane has had one full answer for the grid it is showing.
  bool _probed = false;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return ColoredBox(
      color: SharePalette.pageBg,
      child: ValueListenableBuilder<GridSelection>(
        valueListenable: _selection,
        builder: (context, selection, _) => ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => _body(selection),
        ),
      ),
    );
  }

  Widget _body(GridSelection selection) {
    if (!selection.hasGrid) {
      return const _Blocked(
        title: 'Pick a grid first.',
        message:
            'This screen shares this computer with one grid, and none is '
            'chosen yet. Pick one under Grid and come back.',
      );
    }
    // Only the FIRST probe blanks the page. A later one — the model list
    // re-read after Manage models closes — keeps the page it already has,
    // the way the status rail keeps its last reading through a refresh: the
    // fields on screen are still true, and a form that vanished under the
    // reader every time they came back from a dialog was the older bug.
    if (_controller.loading && !_probed) {
      return const ShareSkeleton(key: Key('share-skeleton'), splitAt: _splitAt);
    }
    if (!_controller.capabilities.cliInstalled) {
      return const _Blocked(
        title: 'The Grid CLI is not on this computer.',
        message:
            "Sharing is the Grid CLI's job — it owns the models on this disk "
            'and the engine that serves them, and Harness does not install it. '
            'Install it, run "grid login", and this screen will find it.',
      );
    }
    final rail = ShareRail(
      gridName: selection.label,
      offers: _controller.capabilities.offers,
      route: _controller.route,
      status: _controller.status,
      onPick: _controller.pickRoute,
    );
    final detail = ShareDetail(
      controller: _controller,
      pull: _pull,
      cli: _cli,
      gridName: selection.label,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _splitAt) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Bounded, because a rail that is one long scrolling column has
                // no bottom to pin its footnote to.
                SizedBox(height: 560, child: rail),
                Divider(height: 1, color: SharePalette.rim),
                SizedBox(height: constraints.maxHeight, child: detail),
              ],
            ),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: ShareMetrics.railWidth, child: rail),
            VerticalDivider(width: 1, color: SharePalette.rim),
            Expanded(child: detail),
          ],
        );
      },
    );
  }
}

/// One thing has to be true before this screen can do anything, and it is not.
class _Blocked extends StatelessWidget {
  const _Blocked({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: ShareType.paneTitle,
            ),
            const SizedBox(height: 9),
            Text(
              message,
              textAlign: TextAlign.center,
              style: ShareType.paneBody,
            ),
          ],
        ),
      ),
    );
  }
}
