import 'package:flutter/material.dart';

import '../../grid/grid_networks_controller.dart';
import '../../grid/grid_selection_store.dart';
import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/theme/share_page_theme.dart';
import 'share_skeleton.dart';
import '../grid_cli.dart';
import '../model_pull.dart';
import '../share_controller.dart';
import '../share_target_store.dart';
import 'share_detail.dart';
import 'share_rail.dart';
import 'share_target_picker.dart';

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
///
/// ### Which grid this page is about
///
/// Its own choice, held in [ShareTargetStore] and resolved by
/// [resolveShareTarget]. It falls back to Settings ▸ Providers' default until
/// somebody picks here, so a machine that never touches the picker behaves the
/// way it did before the picker existed — see that store for why the two are
/// separate questions.
class SharePane extends StatefulWidget {
  const SharePane({
    super.key,
    this.selection,
    this.target,
    this.networks,
    this.cli,
  });

  /// Injected by tests. Null in the app, where the singletons are what the rest
  /// of the app is already showing.
  final GridSelectionStore? selection;
  final ShareTargetStore? target;
  final GridNetworksController? networks;
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
  ShareTargetStore get _target => widget.target ?? shareTargetStore;
  GridNetworksController get _networks =>
      widget.networks ?? gridNetworksController;

  String? _loadedFor;

  /// Whether [_load] has run at all. Separate from [_loadedFor] because null is
  /// a real grid choice here — "none yet" — and not a "never asked" marker.
  bool _loadedOnce = false;

  @override
  void initState() {
    super.initState();
    // Both, because the effective grid is a function of both: the pin, and the
    // default it falls back to when there is no pin.
    _selection.addListener(_load);
    _target.addListener(_load);
    // The picker's rows. Cheap on a second call — only the first one fetches.
    _networks.ensureLoaded();
    _load();
  }

  @override
  void dispose() {
    _selection.removeListener(_load);
    _target.removeListener(_load);
    _controller.dispose();
    _pull.dispose();
    super.dispose();
  }

  ResolvedShareTarget get _resolved =>
      resolveShareTarget(_target.value, _selection.value);

  /// Probe the machine for the chosen grid, once per grid.
  ///
  /// Guarded on the id because both stores notify for things this page does not
  /// care about — a pin landing on the grid the default already named changes
  /// nothing about what to probe — and re-running discovery, three HTTP probes
  /// and two CLI spawns, for that would be work nobody asked for.
  Future<void> _load() async {
    final target = _resolved;
    if (_loadedOnce && target.networkId == _loadedFor) return;
    _loadedOnce = true;
    _loadedFor = target.networkId;
    // A new grid is a new question: blank the page for it.
    _probed = false;
    await _controller.refresh(target.networkId);
    _probed = true;
  }

  /// Whether this pane has had one full answer for the grid it is showing.
  bool _probed = false;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return ColoredBox(
      color: SharePalette.pageBg,
      // One merge rather than three nested builders: the body is a function of
      // all four, and which of them moved makes no difference to what it draws.
      child: ListenableBuilder(
        listenable: Listenable.merge([
          _selection,
          _target,
          _networks,
          _controller,
        ]),
        builder: (context, _) => _body(_resolved),
      ),
    );
  }

  Widget _body(ResolvedShareTarget target) {
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
            'and the engine that serves them. Harness tries to install it when '
            'it starts, so this Mac either could not reach the installer or has '
            'not been restarted since. Install it, run "grid login", and this '
            'screen will find it.',
      );
    }
    final rail = ShareRail(
      gridName: target.label,
      gridPicker: ShareTargetPicker(
        target: target,
        providersDefaultLabel: _selection.value.hasGrid
            ? _selection.value.label
            : '',
        state: _networks.state,
        status: _controller.status,
        onPick: _pin,
        onFollowDefault: _target.followDefault,
      ),
      offers: _controller.capabilities.offers,
      route: _controller.route,
      status: _controller.status,
      onPick: _controller.pickRoute,
    );
    // The rail stays even with no grid chosen, because the control that fixes
    // that is IN it. An earlier version replaced the whole page with a notice
    // telling the reader to go and choose a grid, on the one screen where
    // choosing a grid is now something they can do without leaving.
    final detail = target.hasGrid
        ? ShareDetail(
            controller: _controller,
            pull: _pull,
            cli: _cli,
            gridName: target.label,
          )
        : const _Blocked(
            key: Key('share-no-grid'),
            title: 'Choose a grid to share with.',
            message:
                'This computer serves one grid at a time, and none is chosen. '
                'Pick one under "Grid to share with" on the left — it is this '
                "page's own choice, and it does not move the agents you start.",
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
                SizedBox(height: 640, child: rail),
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

  /// Serve [networkId] from now on, whatever Settings ▸ Providers says.
  ///
  /// Always a pin, even when the grid picked happens to BE the current default:
  /// the reader chose it here, and a choice that silently stayed a
  /// fallback would move their engine the next time somebody changed the
  /// default on another screen.
  void _pin(String networkId, String networkName) =>
      _target.pin(networkId: networkId, networkName: networkName);
}

/// One thing has to be true before this screen can do anything, and it is not.
class _Blocked extends StatelessWidget {
  const _Blocked({super.key, required this.title, required this.message});

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
