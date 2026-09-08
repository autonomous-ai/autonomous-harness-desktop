import 'package:flutter/foundation.dart';

import '../share/grid_cli.dart';
import 'grid_access_type.dart';
import 'grid_api_client.dart';
import 'grid_name.dart';
import 'grid_network.dart';
import 'grid_networks_controller.dart';
import 'grid_selection_store.dart';

/// Where a create stands.
///
/// A sealed family rather than a status enum beside a nullable payload, for the
/// reason [GridNetworksState] gives: the states carry different data, and the
/// dialog switches on them exhaustively instead of juggling booleans.
sealed class CreateGridState {
  const CreateGridState();
}

class CreateGridIdle extends CreateGridState {
  const CreateGridIdle();
}

/// A create is in flight — the dialog shows a spinner in front of the user.
class CreateGridSubmitting extends CreateGridState {
  const CreateGridSubmitting();
}

/// The grid was made. [warning] is set when it exists on the control plane but
/// could not be pulled into this computer's local list — a caveat on a success,
/// not a failure.
class CreateGridDone extends CreateGridState {
  const CreateGridDone(this.network, {this.warning});

  final GridNetwork network;
  final String? warning;
}

class CreateGridFailed extends CreateGridState {
  const CreateGridFailed(this.message);

  /// Already user-facing — [GridApiClient] turns the API's failure shapes into
  /// a sentence before it gets here.
  final String message;
}

/// Where a delete stands. Its own family rather than a flag on [CreateGridState]:
/// the two run from different surfaces and a spinner on one must not appear on
/// the other.
///
/// There is deliberately no `Failed` member. A delete is started from a row
/// that the delete itself removes, so there is nowhere left to draw an error:
/// [GridMutationsController.delete] RETURNS the message and the pane shows it
/// in a snackbar. A failed state kept here would only be a state nothing could
/// ever clear — and a later guard widened to "not idle" would then swallow
/// every delete after the first failure.
sealed class DeleteGridState {
  const DeleteGridState();
}

class DeleteGridIdle extends DeleteGridState {
  const DeleteGridIdle();
}

class DeleteGridDeleting extends DeleteGridState {
  const DeleteGridDeleting(this.networkId);

  /// Which grid is going. The table draws a row at a time, and without this
  /// every row's Delete would spin while one of them ran.
  final String networkId;
}

/// Where a rename stands. Its own family again, for the reason the delete one
/// has: the dialog that runs it must not spin because a delete is in flight.
sealed class RenameGridState {
  const RenameGridState();
}

class RenameGridIdle extends RenameGridState {
  const RenameGridIdle();
}

class RenameGridSaving extends RenameGridState {
  const RenameGridSaving();
}

class RenameGridFailed extends RenameGridState {
  const RenameGridFailed(this.message);
  final String message;
}

/// Creates and deletes grids on the control plane, then puts this computer back
/// in step with what it did.
///
/// Separate from [GridNetworksController], which only ever reads: that one is a
/// cache of `GET /v1/grid/me` shared by two surfaces, and folding writes into it
/// would make every caller of `refresh()` a possible mutation. They meet in one
/// place — a write finishes by asking that controller to reload, so the table,
/// the sidebar pill and the count all move together off one fetch.
///
/// Both operations are three steps, not one: the API call, `grid sync` so the
/// CLI's own `~/.grid` list matches, and a reload here. The sync matters because
/// this app is not the only thing reading that directory — Share Intelligence
/// runs `grid join` out of it, and a grid the CLI has never heard of cannot be
/// joined.
class GridMutationsController extends ChangeNotifier {
  GridMutationsController({
    GridApiClient? client,
    GridCli? cli,
    GridNetworksController? networks,
    GridSelectionStore? selection,
  }) : _client = client ?? GridApiClient(),
       _cli = cli ?? GridCli(),
       _networks = networks ?? gridNetworksController,
       _selection = selection ?? gridSelectionStore;

  final GridApiClient _client;
  final GridCli _cli;
  final GridNetworksController _networks;
  final GridSelectionStore _selection;

  CreateGridState _create = const CreateGridIdle();
  CreateGridState get createState => _create;

  DeleteGridState _delete = const DeleteGridIdle();
  DeleteGridState get deleteState => _delete;

  RenameGridState _rename = const RenameGridIdle();
  RenameGridState get renameState => _rename;

  bool _disposed = false;

  /// True while [networkId] is being deleted — what one row's button reads
  /// rather than "is anything deleting".
  bool isDeleting(String networkId) =>
      _delete is DeleteGridDeleting &&
      (_delete as DeleteGridDeleting).networkId == networkId;

  /// Makes a grid and points this computer at it.
  ///
  /// The name is checked here, before the round-trip: the control plane rejects
  /// a bad one with a validation object rather than a sentence, and two grids
  /// sharing a name are indistinguishable in every list the app draws. The
  /// names already taken come from the loaded grid list, so the check is only as
  /// good as the last refresh — the server is still the authority, and its
  /// answer is shown when it disagrees.
  Future<void> create({
    required String name,
    required GridAccessType type,
  }) async {
    if (_create is CreateGridSubmitting) return;
    final trimmed = name.trim();
    final invalid = gridNameError(trimmed, takenNames: _takenNames());
    if (invalid != null) {
      _setCreate(CreateGridFailed(invalid));
      return;
    }

    _setCreate(const CreateGridSubmitting());
    final GridNetwork network;
    try {
      network = await _client.createNetwork(name: trimmed, type: type);
    } catch (error) {
      _setCreate(CreateGridFailed('$error'));
      return;
    }

    // The grid exists from here on. Everything below is putting the rest of the
    // machine in step with it, and none of it can un-create the grid — so a
    // failure past this line is a warning on a success, never an error.
    final warning = await _syncAndUse(network.networkId);
    await _networks.refresh();
    _setCreate(CreateGridDone(network, warning: warning));
  }

  void resetCreate() => _setCreate(const CreateGridIdle());

  /// Deletes [networkId]. Returns null on success, or the sentence to show.
  ///
  /// The message is returned as well as held in [deleteState] so the caller can
  /// show it after the row that started it is gone — reading state off a
  /// disposed widget is the alternative, and it is a crash.
  Future<String?> delete(String networkId) async {
    if (_delete is DeleteGridDeleting) return null;
    _setDelete(DeleteGridDeleting(networkId));
    try {
      await _client.deleteNetwork(networkId);
    } catch (error) {
      // Back to idle, not to a failed state: the row is still on screen and
      // must be usable again. The message goes back to the caller, which is
      // the only place with somewhere to put it.
      _setDelete(const DeleteGridIdle());
      return '$error';
    }

    // Best-effort, and in this order: the grid is already gone server-side, so
    // a sync that fails leaves a stale local entry rather than a wrong app.
    await _cli.run(['sync']);
    await _reselectIfChosenGridIsGone(networkId);
    await _networks.refresh();
    _setDelete(const DeleteGridIdle());
    return null;
  }

  /// Renames [networkId] to [name]. Returns null on success, or the sentence
  /// to show — the same shape as [delete], and for the same reason: the dialog
  /// closes on success, so the caller cannot read state afterwards.
  ///
  /// Only the display name moves. The grid keeps its id, so nothing already
  /// running against it notices.
  Future<String?> rename({
    required String networkId,
    required String name,
  }) async {
    if (_rename is RenameGridSaving) return null;
    final trimmed = name.trim();
    // Every other grid's name, but not this one's: renaming a grid to what it
    // is already called is not a duplicate, and rejecting it would make the
    // dialog refuse to close on a no-op.
    final invalid = gridNameError(
      trimmed,
      takenNames: _takenNames(exceptId: networkId),
    );
    if (invalid != null) {
      _setRename(RenameGridFailed(invalid));
      return invalid;
    }

    _setRename(const RenameGridSaving());
    try {
      await _client.renameNetwork(networkId, name: trimmed);
    } catch (error) {
      final message = '$error';
      _setRename(RenameGridFailed(message));
      return message;
    }

    // The name has moved server-side. Everything below only catches this
    // computer up, and none of it can fail the rename.
    await _cli.run(['sync']);
    await _renameChosenGrid(networkId: networkId, name: trimmed);
    await _networks.refresh();
    _setRename(const RenameGridIdle());
    return null;
  }

  void resetRename() => _setRename(const RenameGridIdle());

  /// Carry the new name into the saved selection when it names this grid.
  ///
  /// The selection stores the NAME beside the id, on disk, so a reader can put
  /// the grid on screen before anything is fetched. Left alone, the sidebar
  /// pill and the target strip keep printing the retired name — and keep
  /// printing it after a relaunch, because the stale copy is what loads first.
  Future<void> _renameChosenGrid({
    required String networkId,
    required String name,
  }) async {
    if (_selection.value.networkId != networkId) return;
    await _selection.selectNetwork(networkId: networkId, networkName: name);
  }

  /// Pull the new grid into `~/.grid` and make it the CLI's active one.
  ///
  /// `grid sync` re-fetches the list from the saved session — no browser — so
  /// the grid lands locally; `grid use` then points the CLI at it. Returns the
  /// warning to show when the grid exists but this half did not happen.
  Future<String?> _syncAndUse(String networkId) async {
    final sync = await _cli.run(['sync']);
    if (!sync.ok) {
      return sync.installed
          ? 'Created, but refreshing this computer\'s grid list failed: '
                '${sync.errorMessage}'
          : 'Created, but the Grid CLI is not installed here, so this computer '
                'has not been added to it.';
    }
    await _cli.run(['use', networkId]);
    return null;
  }

  /// Move off a grid that has just been deleted.
  ///
  /// The selection is on disk, so leaving it alone does not merely mislead this
  /// session: the next launch reads a remembered id naming a grid that no longer
  /// exists, and every new agent is then launched against nothing. Clearing it
  /// falls back to the engine's own login — the state the app was in before a
  /// grid was ever picked — which is the one honest answer available here.
  /// Picking some other grid on the user's behalf is not: it would silently bill
  /// their next agent to a grid they never chose.
  Future<void> _reselectIfChosenGridIsGone(String networkId) async {
    if (_selection.value.networkId != networkId) return;
    await _selection.clear();
  }

  /// The names to reject a duplicate of — every grid the loaded list knows,
  /// less [exceptId], which a rename passes so a grid is not compared to
  /// itself.
  Iterable<String> _takenNames({String? exceptId}) {
    final state = _networks.state;
    if (state is! GridNetworksReady) return const [];
    return state.me.networks
        .where((network) => network.networkId != exceptId)
        .map((network) => network.name);
  }

  void _setCreate(CreateGridState next) {
    if (_disposed) return;
    _create = next;
    notifyListeners();
  }

  void _setRename(RenameGridState next) {
    if (_disposed) return;
    _rename = next;
    notifyListeners();
  }

  void _setDelete(DeleteGridState next) {
    if (_disposed) return;
    _delete = next;
    notifyListeners();
  }

  @override
  void dispose() {
    // A call outlives the screen when Settings is closed mid-flight, and
    // notifying a disposed ChangeNotifier throws.
    _disposed = true;
    super.dispose();
  }
}
