/// What the model picker offers, worked out away from the widget that draws it.
///
/// The picker is a list of PROVIDERS, each with the models it serves — the
/// shape OpenCode's own model dialog uses, and the shape this app's data has
/// always had: a model id means nothing without the grid that answers for it,
/// and an account is on several. The flat menu this replaced could only ever
/// offer the models of the one provider the sidebar had picked, so moving an
/// agent to a model on another provider meant changing the default for every
/// future agent first, then coming back.
///
/// Pure on purpose. Every state the panel can be in — a provider still loading,
/// one that failed, one serving nothing, a search that matches nothing — is a
/// return value here rather than a branch inside a `build`, so the states that
/// are hard to reach by hand are covered by `test/model_picker_options_test.dart`.
library;

import 'package:flutter/foundation.dart';

import '../grid/agent_grid.dart';
import 'grid_models_controller.dart';
import 'grid_network.dart';
import 'grid_networks_controller.dart';
import 'grid_selection_store.dart' show kNoGridTargetLabel;
import 'node_display.dart' show kAutoModelId, modelKey, withoutGridRunPrefix;

/// What "let the provider choose" is called on screen — the state the launch
/// leaves `ANTHROPIC_MODEL` unset in, distinct from the relay's own virtual
/// `auto` router id (see [kAutoModelId]).
const String kAutoModelLabel = 'Auto';

/// One picked row, in full: a provider, and a model on it.
///
/// The two travel together because they are one decision. An id alone does not
/// say who answers for it, and the agent is retargeted at a relay — so a picker
/// that returned a bare model string would leave its caller to guess the
/// provider, which is exactly the guess that made the old menu single-provider.
@immutable
class ModelChoice {
  const ModelChoice({this.networkId, this.networkName = '', this.model});

  /// The engine's own login — no provider at all. A real choice, not an absence.
  static const none = ModelChoice();

  /// Null means [none]: no provider, so no relay and no key.
  final String? networkId;

  /// The provider's name, carried so a recent row and a snackbar can name it
  /// without another lookup. Never used for matching.
  final String networkName;

  /// Null means Auto — the provider routes for itself.
  final String? model;

  bool get hasProvider => (networkId ?? '').isNotEmpty;

  /// What a row for this choice prints.
  ///
  /// Three states, and the first two are both "no model id": no provider at
  /// all reads as [kNoGridTargetLabel], a provider with no model pinned reads
  /// as Auto. Collapsing them — a null model means Auto — printed "Auto" over
  /// the engine's own login, which is the one row on the list that reaches no
  /// provider to route anything.
  String get label {
    if (!hasProvider) return kNoGridTargetLabel;
    final model = this.model;
    return model == null ? kAutoModelLabel : withoutGridRunPrefix(model);
  }

  @override
  bool operator ==(Object other) =>
      other is ModelChoice &&
      other.networkId == networkId &&
      other.model == model;

  @override
  int get hashCode => Object.hash(networkId, model);

  @override
  String toString() => 'ModelChoice($networkId, $model)';
}

/// One line in the picker's list.
sealed class ModelPickerItem {
  const ModelPickerItem();
}

/// A provider's name, over the models it serves.
class ModelPickerHeader extends ModelPickerItem {
  const ModelPickerHeader(this.title);

  final String title;
}

/// A row that can be picked.
class ModelPickerRow extends ModelPickerItem {
  const ModelPickerRow({required this.choice, this.note});

  final ModelChoice choice;

  /// A quiet aside at the row's end — the provider's name under `Recent`,
  /// where the group header no longer says which one it is.
  final String? note;

  String get label => choice.label;
}

/// A line that exists to be READ, not picked: a provider still answering, one
/// that failed, one serving nothing.
class ModelPickerNote extends ModelPickerItem {
  const ModelPickerNote(this.message);

  final String message;
}

/// What the picker shows, given every provider this computer will offer and
/// whatever the models cache holds for each.
///
/// [providers] is expected to arrive already filtered by
/// `providerEnablementStore`: a provider switched off is not offered anywhere
/// else either, and dimming it here would be a second, unexplained place to
/// discover a choice made in Settings.
///
/// [recents] is the last few picks, most recent first. They are shown only with
/// an empty [query] — a search already puts every match in front of the reader,
/// and a Recent section there would print half of them twice.
List<ModelPickerItem> modelPickerItems({
  required List<GridNetwork> providers,
  required GridModelsState Function(String networkId) modelsOf,
  List<ModelChoice> recents = const [],
  String query = '',
}) {
  final needle = query.trim().toLowerCase();
  final items = <ModelPickerItem>[];

  // First and unconditionally, the way the old menu had it: it is the one row
  // that needs no network call, so it must not be a choice that appears once a
  // fetch lands.
  if (_matches(kNoGridTargetLabel, needle)) {
    items.add(
      const ModelPickerRow(
        choice: ModelChoice.none,
        // Same words the rail's picker puts beside this row: the label names
        // a kind of account, so the note says whose. "The engine's own login"
        // made a reader work out which engine and whose login.
        note: 'on this computer',
      ),
    );
  }

  if (needle.isEmpty) {
    final rows = _recentRows(recents, providers);
    if (rows.isNotEmpty) {
      items
        ..add(const ModelPickerHeader('Recent'))
        ..addAll(rows);
    }
  }

  for (final provider in providers) {
    final section = _providerItems(
      provider,
      modelsOf(provider.networkId),
      needle,
    );
    // No models, no group. See [_providerItems].

    if (section.isEmpty) continue;
    items
      ..add(ModelPickerHeader(provider.displayName))
      ..addAll(section);
  }
  return items;
}

/// One provider's rows — and NOTHING when it has no models to offer.
///
/// ⚠️ A provider that is still answering, that failed, or that serves nothing
/// is dropped from the list entirely: header, note and all. It used to keep its
/// name over a line saying which of those it was, and on an account with four
/// providers that is what the panel mostly was — four names over four
/// apologies, none of them a thing anyone can pick. What is still happening is
/// said ONCE, at the bottom, by [modelPickerModelsNote]; a picker's list is for
/// the choices.
List<ModelPickerRow> _providerItems(
  GridNetwork provider,
  GridModelsState state,
  String needle,
) {
  if (state is! GridModelsReady) return const [];
  // The relay advertises its own virtual router in `/models` (see
  // [kAutoModelId]) whether or not a node is actually serving, so a grid whose
  // only entry is that one has nothing to route to and is EMPTY — offering Auto
  // there would be a row that resolves to nothing.
  final served = [
    for (final model in state.models)
      if (modelKey(model) != kAutoModelId) model,
  ];
  if (served.isEmpty) return const [];
  // A provider's own name brings its whole list: typing it is how a reader says
  // "show me what this one has".
  final nameMatches = _matches(provider.displayName, needle);
  return [
    for (final row in _modelRows(provider, served))
      if (nameMatches || _matches(row.label, needle)) row,
  ];
}

/// The one line under the list saying why it may be shorter than the account
/// is — or null when the list is the whole answer.
///
/// The other half of hiding a provider that has no models: dropping the rows is
/// right, dropping the fact that four grids are still being asked is not, and a
/// reader who opens the panel a second later sees a longer list with no idea
/// why. Said once for all of them rather than once per provider, because the
/// reader's question is "is this everything yet", not "which one is slow".
///
/// A provider serving NOTHING is deliberately silent here: it is not pending
/// and not broken, it is simply a grid with no models, and there is nothing for
/// the reader to wait for or fix.
String? modelPickerModelsNote({
  required List<GridNetwork> providers,
  required GridModelsState Function(String networkId) modelsOf,
}) {
  var pending = 0;
  final failed = <String>[];
  for (final provider in providers) {
    switch (modelsOf(provider.networkId)) {
      // Idle is "not asked yet", which from here is indistinguishable from
      // asking: the panel starts every load as it opens.
      case GridModelsIdle():
      case GridModelsLoading():
        pending++;
      case GridModelsFailed(:final message):
        failed.add(message);
      case GridModelsReady():
        break;
    }
  }
  // Pending outranks failed: it is the one that resolves on its own, and a
  // failure named while three grids are still answering reads as a verdict on
  // the whole list.
  if (pending > 0) return 'Loading models…';
  if (failed.isEmpty) return null;
  // One failure is worth quoting — GridApiClient has already turned it into a
  // sentence with a way out. Several would stack into a paragraph nobody reads,
  // and they are usually the same failure anyway.
  return failed.length == 1
      ? failed.single
      : '${failed.length} providers could not be reached';
}

/// Auto, then every model [served] — the provider's own list with the relay's
/// virtual router already taken out.
///
/// The two Autos are not the same choice, which is why only one of them is ever
/// a row: this one leaves `ANTHROPIC_MODEL` unset, and the relay's would send
/// `ANTHROPIC_MODEL=auto` and leave the header printing the raw id back.
List<ModelPickerRow> _modelRows(GridNetwork provider, List<String> served) => [
  ModelPickerRow(
    choice: ModelChoice(
      networkId: provider.networkId,
      networkName: provider.displayName,
    ),
  ),
  for (final model in served)
    ModelPickerRow(
      choice: ModelChoice(
        networkId: provider.networkId,
        networkName: provider.displayName,
        model: model,
      ),
    ),
];

/// The recent picks that still name a provider this computer offers.
///
/// A recent row is NOT checked against that provider's model list: the list may
/// not have loaded yet, and dropping the section until it does would make the
/// panel's top jump under a reader who opened it to click the row they used
/// last. A model the grid has since stopped serving is refused by the relay,
/// which is where that answer belongs.
List<ModelPickerRow> _recentRows(
  List<ModelChoice> recents,
  List<GridNetwork> providers,
) {
  final byId = {for (final provider in providers) provider.networkId: provider};
  return [
    for (final recent in recents)
      if (byId[recent.networkId ?? ''] case final provider?)
        ModelPickerRow(
          // Rebuilt from the provider rather than replayed from disk: a grid
          // renamed since the pick was made must read under its name now.
          choice: ModelChoice(
            networkId: provider.networkId,
            networkName: provider.displayName,
            model: recent.model,
          ),
          note: provider.displayName,
        ),
  ];
}

bool _matches(String text, String needle) =>
    needle.isEmpty || text.toLowerCase().contains(needle);

/// Where the agent is running NOW, as a row in [items] — or null when it is on
/// a provider this list cannot name.
///
/// Null is a real answer: an agent can be on a grid that was switched off here,
/// or on one belonging to another account entirely. Nothing is then ticked,
/// which is honest — the alternative is ticking a row that is not where the
/// agent actually is.
ModelChoice? currentModelChoice(AgentGrid? grid, List<GridNetwork> providers) {
  if (grid == null) return ModelChoice.none;
  final provider = providerForRelay(grid.baseUrl, providers);
  if (provider == null) return null;
  return ModelChoice(
    networkId: provider.networkId,
    networkName: provider.displayName,
    model: grid.model,
  );
}

/// The provider a relay root belongs to.
///
/// The CLI reports a running agent's assignment as the endpoint its process was
/// handed (`AgentGrid.baseUrl`), and the grid's id is a path segment inside it —
/// `https://grid.autonomous.ai/<network id>/relay/v1`. Matched against the ids
/// this account actually has rather than parsed positionally, so a relay laid
/// out differently (a LAN address, a staging host) still resolves as long as it
/// names the grid at all.
GridNetwork? providerForRelay(String baseUrl, List<GridNetwork> providers) {
  if (baseUrl.isEmpty) return null;
  for (final provider in providers) {
    if (provider.networkId.isNotEmpty && baseUrl.contains(provider.networkId)) {
      return provider;
    }
  }
  return null;
}

/// The next pickable row from [from], [delta] steps away — headers and notes
/// skipped, because a keyboard walking the list must land only where Enter
/// means something.
///
/// Stops at the ends rather than wrapping: a list this long is scrolled, and a
/// highlight that jumped from the last row to the first would read as the panel
/// having scrolled rather than the selection having moved.
int? nextPickableIndex(List<ModelPickerItem> items, int? from, int delta) {
  if (items.isEmpty) return null;
  var index = from ?? (delta > 0 ? -1 : items.length);
  while (true) {
    index += delta;
    if (index < 0 || index >= items.length) return from;
    if (items[index] is ModelPickerRow) return index;
  }
}

/// The first row Enter would pick — where the highlight starts, and where it
/// returns after every keystroke in the search field.
int? firstPickableIndex(List<ModelPickerItem> items) =>
    nextPickableIndex(items, null, 1);

/// Where [choice] sits in [items], or null when it is not offered.
int? indexOfChoice(List<ModelPickerItem> items, ModelChoice? choice) {
  if (choice == null) return null;
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    if (item is ModelPickerRow && item.choice == choice) return i;
  }
  return null;
}

/// The one line a provider picker shows INSTEAD of an account's providers —
/// while the list is still loading, when this computer has no Grid session, and
/// when the fetch failed. Null once the providers have landed: there is then
/// nothing to say that the list does not say better.
///
/// Shared with the sidebar's provider pill (`gridTargetMenuOptions`), which
/// draws the same three states as its own disabled row. Two pickers wording
/// "we could not reach the control plane" differently is how one app ends up
/// with two accounts of the same failure.
String? providerLoadNote(GridNetworksState state) => switch (state) {
  GridNetworksIdle() || GridNetworksLoading() => 'Loading providers…',
  // Signing in is a real action with a real failure mode, and neither a menu
  // hanging off a pill nor a picker opened to change one agent is the place to
  // run it. Settings ▸ Providers has the button.
  GridNetworksSignedOut() => 'Sign in to Grid in Settings',
  // Already user-facing — GridApiClient turns the API's failure shapes into a
  // sentence.
  GridNetworksFailed(:final message) => message,
  GridNetworksReady() => null,
};
