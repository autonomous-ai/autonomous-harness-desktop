import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../analytics/analytics.dart';
import '../../grid/grid_mutations_controller.dart';
import '../../grid/grid_network.dart';
import '../../grid/grid_networks_controller.dart';
import '../../grid/grid_selection_store.dart';
import '../../grid/provider_enablement_store.dart';
import '../../grid/grid_session.dart';
import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/widgets/app_icon_button.dart';
import '../../shared/widgets/section_scaffold.dart';
import '../../shared/widgets/skeleton.dart';
import '../../widgets/share_grid/share_grid_dialog.dart';
import 'create_grid_dialog.dart';
import 'provider_split_pane.dart';
import 'rename_grid_dialog.dart';

/// Settings ▸ Providers: which providers this computer will use, and which one
/// new agents launch against.
///
/// Read straight from the Grid control plane over HTTPS — this screen does not
/// go through the `harness` CLI, which knows nothing about Grid accounts. See
/// [GridApiClient].
///
/// The pane is a **split**: a rail of every provider on the left, and on the
/// right everything about the one the rail has selected ([ProviderSplitPane]).
/// The headline card this replaced repeated the chosen provider's name, access
/// rule and owner — facts the selected row already carried — so the panel now
/// IS the headline, describing whatever is selected rather than whatever is in
/// force. Choosing a default here retargets nothing that is already running;
/// the subtitle is what says so.
class GridSection extends StatefulWidget {
  const GridSection({
    super.key,
    required this.controller,
    this.selection,
    this.session,
    this.harnessEmail,
    this.mutations,
    this.enablement,
  });

  final GridNetworksController controller;

  /// Injected by tests. The app uses the shared singleton, which is what lets
  /// this pane and the New agent dialog change the same choice.
  final GridSelectionStore? selection;

  /// Injected by tests too — the Grid sign-in this pane offers when the machine
  /// has none. The app uses the singleton every other reader shares, so a
  /// sign-in here is a sign-in for the status rail and the share sheet as well.
  final GridSessionStore? session;

  /// Who the app is signed in to Harness as, for the one comparison nothing
  /// else makes — see [_AccountMismatch]. Null before the profile lands.
  final String? harnessEmail;

  /// Which providers this computer will use, injected by tests. The app uses
  /// the shared singleton, so a switch here reaches the sidebar's pill too.
  final ProviderEnablementStore? enablement;

  /// Creating and deleting, injected by tests. The app builds one per visit to
  /// this pane: unlike [GridNetworksController] it caches nothing worth sharing
  /// — it holds only what is in flight right now.
  final GridMutationsController? mutations;

  @override
  State<GridSection> createState() => _GridSectionState();
}

class _GridSectionState extends State<GridSection> {
  String _query = '';
  _GridFilter _filter = _GridFilter.all;
  late final GridMutationsController _mutations;

  /// Only an injected one is left alone — a controller this pane made is this
  /// pane's to dispose, and one it was handed belongs to whoever passed it.
  bool _ownsMutations = false;

  GridSelectionStore get _selection => widget.selection ?? gridSelectionStore;

  ProviderEnablementStore get _enablement =>
      widget.enablement ?? providerEnablementStore;

  @override
  void initState() {
    super.initState();
    _ownsMutations = widget.mutations == null;
    _mutations =
        widget.mutations ??
        GridMutationsController(networks: widget.controller);
  }

  @override
  void dispose() {
    if (_ownsMutations) _mutations.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    // Cheap on every rebuild: only the first call fetches.
    widget.controller.ensureLoaded();
    // The whole pane, heading included, hangs off the controller: the count
    // beside the title is part of the load, so a scaffold built outside this
    // builder would keep saying nothing after the grids arrived.
    // BOTH controllers, not just the list: the table reads `isDeleting` off
    // the mutations controller to spin one row, and a builder listening only
    // to the list would leave that row saying "Delete grid" for the whole
    // call — the click would look like it did nothing.
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.controller,
        _mutations,
        _enablement,
      ]),
      builder: (context, _) {
        final state = widget.controller.state;
        final total = state is GridNetworksReady
            ? state.me.networks.length
            : null;
        final loading =
            state is GridNetworksIdle || state is GridNetworksLoading;
        final countStyle = TextStyle(
          color: grid.AppPalette.textFaint,
          fontSize: 12.5,
        );
        return SectionScaffold(
          title: 'Providers',
          // The count is part of the load, so while it is unknown the heading
          // wears a bar of the same height rather than nothing: a heading that
          // grows a figure a beat after the table is a heading that moved.
          titleTrailing: total == null
              ? (loading
                    ? SkeletonText(
                        key: const Key('grid-count-skeleton'),
                        style: countStyle,
                        width: 44,
                      )
                    : null)
              : Text(
                  _countLabel(total, state),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: countStyle,
                ),
          subtitle:
              'Every provider this account can reach. Enabled providers are '
              'available to your agents; the default is the one new agents '
              'launch against. Agents already running stay where they are.',
          child: switch (state) {
            // The headline does not wait on the network — the chosen grid's
            // NAME is on disk beside its id — so it is real from the first
            // frame, and only its facts and actions arrive with the fetch.
            // Only the table and the count are placeholders.
            GridNetworksIdle() || GridNetworksLoading() => _body(null, null),
            GridNetworksSignedOut() => _SignedOut(
              session: widget.session,
              onSignedIn: () => unawaited(widget.controller.refresh()),
            ),
            GridNetworksFailed(:final message) => _Failed(
              message: message,
              onRetry: () => unawaited(widget.controller.refresh()),
            ),
            GridNetworksReady(:final me) => _body(me.user, me.networks),
          },
        );
      },
    );
  }

  /// The Grid account, when it is not the Harness one — the state the bootstrap
  /// sign-in deliberately leaves alone.
  ///
  /// Null while either address is unknown: "we have not asked yet" and "they
  /// differ" must not draw the same, and a warning that flashes on every open
  /// while the profile loads is a warning people stop reading.
  String? _mismatch(String? gridEmail) {
    final harness = widget.harnessEmail?.trim();
    final grid = gridEmail?.trim();
    if (harness == null || harness.isEmpty) return null;
    if (grid == null || grid.isEmpty) return null;
    return grid.toLowerCase() == harness.toLowerCase() ? null : grid;
  }

  /// How many providers there are, and how many of them this computer will
  /// use — two figures because they answer different questions, and a count
  /// alone would hide a machine that has switched all but one off.
  String _countLabel(int total, GridNetworksState state) {
    final plural = total == 1 ? '' : 's';
    if (state is! GridNetworksReady) return '$total provider$plural';
    final enabled = state.me.networks
        .where((n) => _enablement.isEnabled(n.networkId))
        .length;
    return '$total provider$plural · $enabled enabled';
  }

  /// The pane's one layout, with or without its answer. [user] and [networks]
  /// are null while the providers load, and every part that depends on them is
  /// then drawn at its final size and left blank.
  Widget _body(GridUser? user, List<GridNetwork>? networks) {
    final email = user?.email;
    final visible = email == null || networks == null
        ? null
        : _visible(email, networks);
    // Both stores, because the pane reads both on every frame: which provider
    // new agents use, and which ones this computer will offer at all. Nested
    // rather than merged into one listenable so each rebuild names its own
    // cause — and because they hold different types.
    return ValueListenableBuilder<GridSelection>(
      valueListenable: _selection,
      builder: (context, chosen, _) =>
          ValueListenableBuilder<Set<String>>(
            valueListenable: _enablement,
            builder: (context, _, _) {
              final allOff =
                  networks != null &&
                  networks.isNotEmpty &&
                  networks.every((n) => !_enablement.isEnabled(n.networkId));
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_mismatch(email) case final String gridEmail) ...[
                    _AccountMismatch(
                      gridEmail: gridEmail,
                      harnessEmail: widget.harnessEmail!,
                    ),
                    const SizedBox(height: 12),
                  ],
                  // Above the split rather than inside it: the consequence is
                  // about the pane as a whole, not about any one provider, and
                  // a reader scanning down meets it before the switches that
                  // caused it.
                  if (allOff) ...[
                    const ProviderAllOffBanner(),
                    const SizedBox(height: 12),
                  ],
                  _FilterBar(
                    query: _query,
                    filter: _filter,
                    shown: visible?.length,
                    total: networks?.length,
                    email: email,
                    onQuery: (value) => setState(() => _query = value),
                    onFilter: (value) => setState(() => _filter = value),
                    onReload: () => unawaited(widget.controller.refresh()),
                    onCreate: user == null
                        ? null
                        : () => unawaited(_create(user)),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: visible == null
                        ? const ProviderSplitPaneSkeleton(
                            key: Key('provider-split-skeleton'),
                          )
                        : ProviderSplitPane(
                            networks: visible,
                            signedInEmail: email!,
                            defaultId: chosen.networkId,
                            filtered: visible.length != networks!.length,
                            isEnabled: (network) =>
                                _enablement.isEnabled(network.networkId),
                            onToggleEnabled: _toggleEnabled,
                            onMakeDefault: _makeDefault,
                            onShare: _share,
                            onRename: _rename,
                            onDelete: _confirmDelete,
                            isDeleting: _mutations.isDeleting,
                          ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'A provider is where new agents get their credentials. '
                    'Each agent picks its own model from its header.',
                    style: TextStyle(
                      color: grid.AppPalette.textFaint,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              );
            },
          ),
    );
  }

  /// Point new agents at [network].
  void _makeDefault(GridNetwork network) {
    analytics.gridPicked(source: 'settings', networkId: network.networkId);
    unawaited(
      _selection.selectNetwork(
        networkId: network.networkId,
        networkName: network.displayName,
      ),
    );
  }

  /// Turn a provider on or off for this computer.
  ///
  /// Switching the DEFAULT off does not refuse the click — it hands the default
  /// to the next enabled provider, or clears it when there is none left, which
  /// is the state [ProviderAllOffBanner] then explains. The alternative was a
  /// dialog telling the user to go and change something else first, which is a
  /// screen refusing to do the obvious thing on the user's behalf.
  void _toggleEnabled(GridNetwork network, bool enabled) {
    unawaited(_enablement.setEnabled(network.networkId, enabled));
    if (enabled) return;
    if (_selection.value.networkId != network.networkId) return;

    final state = widget.controller.state;
    final all = state is GridNetworksReady
        ? state.me.networks
        : const <GridNetwork>[];
    for (final candidate in all) {
      if (candidate.networkId == network.networkId) continue;
      if (!_enablement.isEnabled(candidate.networkId)) continue;
      _makeDefault(candidate);
      return;
    }
    // Nothing left to hand it to.
    analytics.gridPicked(source: 'settings', networkId: null);
    unawaited(_selection.clear());
  }

  /// Invite people to a provider.
  void _share(GridNetwork network) => unawaited(
    showShareGridDialog(
      context,
      networkId: network.networkId,
      gridName: network.displayName,
      networks: widget.controller,
    ),
  );

  /// Open the create form, and say what happened afterwards.
  ///
  /// The result is announced HERE rather than inside the dialog: the dialog is
  /// gone by the time there is anything to say, and a line that flashes for one
  /// frame on the way out is no better than one never printed. A warning means
  /// the grid was made but this computer's own list did not catch up — worth
  /// saying, and not an error.
  Future<void> _create(GridUser user) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = await showCreateGridDialog(
      context,
      controller: _mutations,
      gatedDomain: user.gatedDomain,
    );
    if (name == null) return;
    final state = _mutations.createState;
    final warning = state is CreateGridDone ? state.warning : null;
    messenger.showSnackBar(
      SnackBar(content: Text(warning ?? 'Provider “$name” created.')),
    );
  }

  /// Open the rename form, and name the result afterwards.
  ///
  /// Said here rather than inside the dialog, for the reason [_create] gives:
  /// the dialog is gone by the time there is anything to say.
  Future<void> _rename(GridNetwork network) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = await showRenameGridDialog(
      context,
      controller: _mutations,
      network: network,
    );
    if (name == null) return;
    messenger.showSnackBar(SnackBar(content: Text('Renamed to "$name".')));
  }

  /// Delete a grid, then say what happened.
  ///
  /// The message comes back from the controller rather than being read off its
  /// state afterwards: the row that started this is gone by then, and reading
  /// state through a disposed widget is a crash rather than a blank line.
  Future<void> _confirmDelete(GridNetwork network) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = network.displayName;
    final error = await _mutations.delete(network.networkId);
    messenger.showSnackBar(
      SnackBar(content: Text(error ?? 'Deleted "$name".')),
    );
  }






  /// The grids the filter and the query leave standing.
  ///
  /// Matching is a plain case-insensitive substring across the fields a person
  /// would type — the name, the id, the owner, the type, the roles — for the
  /// reason the settings rail's own filter gives: anything cleverer is
  /// machinery nobody can feel.
  List<GridNetwork> _visible(String email, List<GridNetwork> networks) {
    final query = _query.trim().toLowerCase();
    return [
      for (final network in networks)
        if (_filter.admits(network, email) &&
            (query.isEmpty || _haystack(network).contains(query)))
          network,
    ];
  }

  String _haystack(GridNetwork network) => [
    network.displayName,
    network.networkId,
    network.ownerEmail,
    network.networkType,
    ...?network.member?.roles,
  ].join(' ').toLowerCase();
}

/// The three questions worth asking of a list of providers.
///
/// Not a general facet builder: these are the axes that decide whether a
/// provider is one you can act on — is it mine, and does it route.
///
/// ⚠️ There was a fourth, `Enabled`, and it was removed because the word was
/// already on screen meaning something else: the panel's own ENABLED sits
/// beside the switch that CHANGES the thing, 400px from a chip that only hid
/// rows. One word, two meanings, one of them a control and one of them a
/// filter — which is exactly the confusion a person reported. The switch is on
/// every rail row anyway, so the eye does this filter's work for it, and the
/// heading's `N enabled` still answers the question it asked.
enum _GridFilter {
  all('All'),
  owned('You own'),
  // "Has a router", not "Router on": the second reads as a state this control
  // puts the provider INTO, which is the same misreading `Enabled` caused —
  // and the panel a few hundred pixels away really does print `router on` as a
  // fact about the provider. A filter's label should name what it keeps.
  router('Has a router');

  const _GridFilter(this.label);

  final String label;

  bool admits(GridNetwork network, String email) => switch (this) {
    _GridFilter.all => true,
    _GridFilter.owned => network.isOwnedBy(email),
    _GridFilter.router => network.routerEnabled,
  };
}

/// Narrow the table, and say whose grids these are.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.query,
    required this.filter,
    required this.shown,
    required this.total,
    required this.email,
    required this.onQuery,
    required this.onFilter,
    required this.onReload,
    required this.onCreate,
  });

  final String query;
  final _GridFilter filter;

  /// All three null while the grids load: the controls are real (a query
  /// typed early is kept), the line that names whose grids these are is not.
  final int? shown;
  final int? total;
  final String? email;
  final ValueChanged<String> onQuery;
  final ValueChanged<_GridFilter> onFilter;
  final VoidCallback onReload;

  /// Null until the grid list has loaded. Creating needs the names already
  /// taken (to reject a duplicate before the round-trip) and the account's own
  /// domain (to know whether the domain rule may even be offered) — both come
  /// from the same fetch, and offering the button before it lands would open a
  /// form that cannot answer its own questions.
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 210,
                child: TextField(
                  key: const Key('grid-filter-field'),
                  onChanged: onQuery,
                  style: grid.kFieldTextStyle,
                  decoration: InputDecoration(
                    hintText: 'Filter providers',
                    prefixIcon: Icon(
                      LucideIcons.search300,
                      size: grid.kFieldIconSize,
                      color: grid.AppPalette.textFaint,
                    ),
                  ),
                ),
              ),
              for (final option in _GridFilter.values)
                _Chip(
                  label: option.label,
                  selected: option == filter,
                  onTap: () => onFilter(option),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Capped rather than flexible: a `Flexible` here has the same flex as
        // the search-and-chips side and so reserves half the bar for an email
        // and a 16px button, which is what pushed the last chip onto a line of
        // its own. Bounded, it takes what it needs and the filters keep the
        // rest.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: email == null
                    ? const SkeletonText(
                        style: TextStyle(fontSize: 12),
                        width: 150,
                        alignment: Alignment.centerRight,
                      )
                    : Text(
                        // The plain total lives on the heading now. This line
                        // says whose providers these are, and speaks up only when
                        // the filter is hiding some of them.
                        shown == total
                            ? email!
                            : '$shown of $total providers · $email',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: grid.AppPalette.textFaint,
                          fontSize: 12,
                        ),
                      ),
              ),
              const SizedBox(width: 6),
              AppIconButton(
                key: const Key('grid-refresh-button'),
                icon: LucideIcons.refreshCw300,
                size: 16,
                tooltip: 'Reload providers',
                onPressed: onReload,
              ),
              const SizedBox(width: 6),
              // Labelled, not a bare glyph. Creating a grid is the one thing on
              // this bar that MAKES something rather than filtering or
              // reloading what is already there, and a lone `+` beside the
              // reload icon read as a second, quieter icon rather than as the
              // pane's only constructive action.
              OutlinedButton.icon(
                key: const Key('grid-create-button'),
                onPressed: onCreate,
                style: OutlinedButton.styleFrom(
                  // Restated for the reason `_textButtonStyle` gives: a
                  // `styleFrom` replaces the theme's whole style, hover wash
                  // included, and NoSplash leaves nothing in its place.
                  overlayColor: grid.AppSurface.hoverFill,
                  minimumSize: const Size(0, grid.AppControl.heightSmall),
                  padding: grid.AppControl.paddingSmallIcon,
                  textStyle: TextStyle(
                    fontFamily: grid.AppFont.sans,
                    fontSize: 12.5,
                  ),
                ),
                icon: const Icon(
                  LucideIcons.plus300,
                  size: grid.AppControl.iconSize,
                ),
                label: const Text('New provider'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A filter's on/off state, in the app's accent wash — the same treatment the
/// rail gives the section you are in, because it means the same thing: this is
/// what you are looking at.
class _Chip extends StatefulWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Chip> createState() => _ChipState();
}

class _ChipState extends State<_Chip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: grid.AppMotion.hover,
          curve: grid.AppMotion.curve,
          height: grid.AppControl.height,
          // Padding, and NOT `alignment` — a Container with an alignment wraps
          // its child in an unbounded Align, which fills whatever it is offered.
          // Inside the filter bar's Wrap that is the bar's whole width, so each
          // chip took a run of its own and the row came out as a stack of
          // full-width bars.
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: widget.selected
                ? grid.AppPalette.accent
                : (_hovered ? grid.AppSurface.hoverFill : Colors.transparent),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: widget.selected
                  ? grid.AppPalette.accent
                  : grid.AppGlass.hair,
            ),
          ),
          child: Center(
            widthFactor: 1,
            child: Text(
              widget.label,
              style: TextStyle(
                color: widget.selected
                    ? Colors.white
                    : grid.AppPalette.textSecondary,
                fontSize: 12,
                fontWeight: widget.selected
                    ? grid.AppFont.semibold
                    : grid.AppFont.regular,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The load failed — say what went wrong and leave a way to try again, rather
/// than an empty pane that looks like an account with no grids.
class _Failed extends StatelessWidget {
  const _Failed({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Align(
      alignment: Alignment.topLeft,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: grid.AppPalette.warn.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: grid.AppPalette.warn.withValues(alpha: 0.26),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  LucideIcons.triangleAlert300,
                  size: 16,
                  color: grid.AppPalette.warn,
                ),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    'Could not load your providers',
                    style: TextStyle(
                      color: grid.AppPalette.textPrimary,
                      fontSize: 12.5,
                      fontWeight: grid.AppFont.semibold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: TextStyle(
                color: grid.AppPalette.textSecondary,
                fontSize: 12,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('grid-retry-button'),
                onPressed: onRetry,
                child: const Text(
                  'Try again',
                  style: TextStyle(fontSize: 12.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// No Grid sign-in on this computer, and the one button that fixes it.
///
/// Its own surface rather than a [_Failed] with a different label: this is not
/// an error, it is the state every machine starts in. `harness grid login`
/// hands the Harness session the app already has to the Grid CLI, so there is
/// no browser and nothing to type — which is why offering the button here is
/// better than telling somebody to open a terminal.
class _SignedOut extends StatefulWidget {
  const _SignedOut({required this.onSignedIn, this.session});

  final VoidCallback onSignedIn;

  /// Tests pass one; the app uses the singleton every other reader does.
  final GridSessionStore? session;

  @override
  State<_SignedOut> createState() => _SignedOutState();
}

class _SignedOutState extends State<_SignedOut> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final failure = await (widget.session ?? gridSessionStore).signIn();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = failure;
    });
    if (failure == null) widget.onSignedIn();
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final error = _error;
    return Align(
      alignment: Alignment.topLeft,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: grid.AppGlass.surfaceFill,
          borderRadius: BorderRadius.circular(9),
          boxShadow: grid.AppGlass.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "You're not signed in to Grid",
              style: TextStyle(
                color: grid.AppPalette.textPrimary,
                fontSize: 12.5,
                fontWeight: grid.AppFont.semibold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Grid is a separate account from Harness. Signing in reuses the '
              'Harness session this app already has, so there is no browser '
              'and nothing to type.',
              style: TextStyle(
                color: grid.AppPalette.textSecondary,
                fontSize: 12,
                height: 1.45,
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              // The CLI's own sentence, verbatim: every one of its refusals
              // already names the way forward, and re-wording them here would
              // be a second opinion about a failure this app did not have.
              Text(
                error,
                key: const Key('grid-sign-in-error'),
                style: TextStyle(
                  color: grid.AppPalette.warn,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                key: const Key('grid-sign-in-button'),
                onPressed: _busy ? null : () => unawaited(_signIn()),
                child: Text(_busy ? 'Signing in…' : 'Sign in to Grid'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Grid CLI is signed in as somebody other than the Harness account.
///
/// A statement, not a fix. The app signs this computer in to Grid only when it
/// has NO session (`AppNotifier._ensureGridSession`), precisely so a session
/// somebody pointed at another account on purpose is never overwritten — which
/// leaves exactly one duty here: to say so, rather than let a person read
/// another account's grids without ever being told whose they are.
class _AccountMismatch extends StatelessWidget {
  const _AccountMismatch({required this.gridEmail, required this.harnessEmail});

  final String gridEmail;
  final String harnessEmail;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Container(
      key: const Key('grid-account-mismatch'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: grid.AppPalette.warn.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: grid.AppPalette.warn.withValues(alpha: 0.26)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            LucideIcons.triangleAlert300,
            size: 15,
            color: grid.AppPalette.warn,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'These are $gridEmail\'s providers. Harness is signed in as '
              '$harnessEmail. Run `harness grid logout`, then `harness grid '
              'login`, to use the Harness account here.',
              style: TextStyle(
                color: grid.AppPalette.textSecondary,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
