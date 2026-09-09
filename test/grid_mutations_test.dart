// Creating and deleting a grid: the two calls in this app that CHANGE something
// on the Grid control plane. Everything else there only reads, so the ordering
// these tests pin — API first, then the local CLI, then the shared list — is
// not covered anywhere else.
import 'package:flutter_test/flutter_test.dart';

import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/grid/grid_access_type.dart';
import 'package:harness/grid/grid_mutations_controller.dart';
import 'package:harness/grid/grid_name.dart';
import 'package:harness/grid/grid_network.dart';
import 'package:harness/grid/grid_networks_controller.dart';
import 'package:harness/grid/grid_selection_store.dart';
import 'package:harness/share/grid_cli.dart';

import 'support/fake_grid_api.dart';

class _MemoryStore implements LocalKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// A control plane that records the writes and can be made to refuse one.
class _Api extends FakeGridApi {
  _Api({this.createError, this.deleteError, this.renameError});

  final String? createError;
  final String? deleteError;
  final String? renameError;

  final List<({String name, GridAccessType type})> created = [];
  final List<String> deleted = [];
  final List<({String id, String name})> renamed = [];

  @override
  Future<GridNetwork> createNetwork({
    required String name,
    required GridAccessType type,
  }) async {
    if (createError != null) throw Exception(createError);
    created.add((name: name, type: type));
    return GridNetwork.fromJson({
      'network_id': 'grid-new',
      'name': name,
      'owner_email': 'huy@example.com',
      'network_type': type.wire,
      'status': 'active',
      'router_enabled': false,
      'router_advisors': const [],
    });
  }

  @override
  Future<void> deleteNetwork(String networkId) async {
    if (deleteError != null) throw Exception(deleteError);
    deleted.add(networkId);
  }

  @override
  Future<void> renameNetwork(String networkId, {required String name}) async {
    if (renameError != null) throw Exception(renameError);
    renamed.add((id: networkId, name: name));
  }
}

/// A `grid` CLI that records its arguments instead of running anything.
class _Cli extends GridCli {
  _Cli({this.installed = true, this.exitCode = 0})
    : super(environment: const {'HOME': '/tmp/fake-home'});

  final bool installed;
  final int exitCode;
  final List<List<String>> ran = [];

  @override
  Future<String?> locate() async => installed ? '/usr/local/bin/grid' : null;

  @override
  Future<GridCliResult> run(List<String> arguments) async {
    if (!installed) return GridCliResult.notInstalled;
    ran.add(arguments);
    return GridCliResult(
      exitCode: exitCode,
      stdout: '',
      stderr: exitCode == 0 ? '' : 'the CLI said no',
    );
  }
}

/// A loaded networks controller, so a create can see the names already taken.
Future<GridNetworksController> _loadedNetworks(FakeGridApi api) async {
  final networks = GridNetworksController(client: api);
  await networks.refresh();
  return networks;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('gridNameError', () {
    test('accepts an ordinary name', () {
      expect(gridNameError('my team grid'), isNull);
      expect(gridNameError('hp-1.1_x'), isNull);
    });

    test('refuses an empty name', () {
      expect(gridNameError('   '), 'Enter a name for your provider.');
    });

    test('refuses one past the length the control plane accepts', () {
      expect(gridNameError('a' * (gridNameMaxLength + 1)), isNotNull);
      expect(gridNameError('a' * gridNameMaxLength), isNull);
    });

    test('refuses a name that does not start with a letter or digit', () {
      expect(gridNameError('-leading'), isNotNull);
      expect(gridNameError('a/b'), isNotNull);
    });

    // Two grids with the same name are indistinguishable in every list the app
    // draws, so this is rejected before the round-trip rather than after it.
    test('refuses a duplicate, ignoring case and surrounding space', () {
      expect(
        gridNameError('Water Grid', takenNames: const ['  water grid ']),
        'You already have a provider called "Water Grid".',
      );
      expect(gridNameError('other', takenNames: const ['water grid']), isNull);
    });
  });

  group('accessTypesFor', () {
    test('offers the domain rule only to an account that may use it', () {
      expect(
        accessTypesFor(canRestrictToDomain: true),
        contains(GridAccessType.domain),
      );
      expect(
        accessTypesFor(canRestrictToDomain: false),
        isNot(contains(GridAccessType.domain)),
      );
    });

    test('names the domain in the label and the sentence under it', () {
      expect(
        accessLabelFor(GridAccessType.domain, domain: 'autonomous.ai'),
        '@autonomous.ai emails',
      );
      expect(
        accessDescriptionFor(GridAccessType.domain, domain: 'autonomous.ai'),
        contains('@autonomous.ai'),
      );
      // With no domain to name it falls back rather than printing a bare "@".
      expect(accessLabelFor(GridAccessType.domain), 'My domain');
    });
  });

  group('GridUser', () {
    test('gates the domain on the flag, not on the address alone', () {
      final allowed = GridUser.fromJson({
        'email_domain': 'autonomous.ai',
        'can_restrict_to_domain': true,
      });
      final refused = GridUser.fromJson({
        'email_domain': 'gmail.com',
        'can_restrict_to_domain': false,
      });
      expect(allowed.gatedDomain, 'autonomous.ai');
      expect(refused.gatedDomain, isNull);
    });
  });

  group('create', () {
    test('calls the API, syncs the CLI, then reloads the list', () async {
      final api = _Api();
      final cli = _Cli();
      final networks = await _loadedNetworks(api);
      final controller = GridMutationsController(
        client: api,
        cli: cli,
        networks: networks,
        selection: GridSelectionStore(storage: _MemoryStore()),
      );

      await controller.create(name: '  new grid  ', type: GridAccessType.anyone);

      expect(api.created.single.name, 'new grid');
      expect(api.created.single.type, GridAccessType.anyone);
      // Synced so the Grid CLI's own list knows the grid, then made active.
      expect(cli.ran, [
        ['sync'],
        ['use', 'grid-new'],
      ]);
      // The list was fetched once by the load and once by the create.
      expect(api.calls, 2);
      final state = controller.createState;
      expect(state, isA<CreateGridDone>());
      expect((state as CreateGridDone).warning, isNull);
    });

    test('refuses a duplicate name without calling the API', () async {
      final api = _Api();
      final cli = _Cli();
      final networks = await _loadedNetworks(api);
      final controller = GridMutationsController(
        client: api,
        cli: cli,
        networks: networks,
        selection: GridSelectionStore(storage: _MemoryStore()),
      );

      await controller.create(
        name: 'water grid',
        type: GridAccessType.restricted,
      );

      expect(api.created, isEmpty);
      expect(cli.ran, isEmpty);
      expect(controller.createState, isA<CreateGridFailed>());
    });

    test('reports the control plane refusal in the dialog', () async {
      final api = _Api(createError: 'quota reached');
      final networks = await _loadedNetworks(api);
      final controller = GridMutationsController(
        client: api,
        cli: _Cli(),
        networks: networks,
        selection: GridSelectionStore(storage: _MemoryStore()),
      );

      await controller.create(name: 'fresh', type: GridAccessType.restricted);

      final state = controller.createState;
      expect(state, isA<CreateGridFailed>());
      expect((state as CreateGridFailed).message, contains('quota reached'));
    });

    // The grid exists once the POST lands. Nothing after that can un-create it,
    // so a local sync that fails is a caveat on a success, never an error.
    test('a failed sync is a warning, not a failure', () async {
      final api = _Api();
      final networks = await _loadedNetworks(api);
      final controller = GridMutationsController(
        client: api,
        cli: _Cli(exitCode: 1),
        networks: networks,
        selection: GridSelectionStore(storage: _MemoryStore()),
      );

      await controller.create(name: 'fresh', type: GridAccessType.restricted);

      final state = controller.createState;
      expect(state, isA<CreateGridDone>());
      expect((state as CreateGridDone).warning, isNotNull);
      expect(state.network.name, 'fresh');
    });

    test('says so when the Grid CLI is not installed here', () async {
      final api = _Api();
      final networks = await _loadedNetworks(api);
      final controller = GridMutationsController(
        client: api,
        cli: _Cli(installed: false),
        networks: networks,
        selection: GridSelectionStore(storage: _MemoryStore()),
      );

      await controller.create(name: 'fresh', type: GridAccessType.restricted);

      final state = controller.createState as CreateGridDone;
      expect(state.warning, contains('not installed'));
    });
  });

  group('delete', () {
    test('calls the API, syncs, and reloads', () async {
      final api = _Api();
      final cli = _Cli();
      final networks = await _loadedNetworks(api);
      final controller = GridMutationsController(
        client: api,
        cli: cli,
        networks: networks,
        selection: GridSelectionStore(storage: _MemoryStore()),
      );

      expect(await controller.delete('grid-aaf6a46ced4f42f9'), isNull);

      expect(api.deleted, ['grid-aaf6a46ced4f42f9']);
      expect(cli.ran, [
        ['sync'],
      ]);
      expect(api.calls, 2);
      expect(controller.deleteState, isA<DeleteGridIdle>());
    });

    // The selection is on disk. Left naming a grid that no longer exists, the
    // NEXT launch reads it back and launches every new agent against nothing.
    test('clears the saved selection when it named the deleted grid', () async {
      final api = _Api();
      final storage = _MemoryStore();
      final selection = GridSelectionStore(storage: storage);
      await selection.selectNetwork(
        networkId: 'grid-aaf6a46ced4f42f9',
        networkName: 'hp-1-1',
      );
      final controller = GridMutationsController(
        client: api,
        cli: _Cli(),
        networks: await _loadedNetworks(api),
        selection: selection,
      );

      await controller.delete('grid-aaf6a46ced4f42f9');

      expect(selection.value.hasGrid, isFalse);
      expect(storage.values['grid_selected_network_id'], isNull);
    });

    test('leaves a selection that named a different grid alone', () async {
      final api = _Api();
      final selection = GridSelectionStore(storage: _MemoryStore());
      await selection.selectNetwork(
        networkId: 'grid-e3b210eacc5b4cdf',
        networkName: 'Water Grid',
      );
      final controller = GridMutationsController(
        client: api,
        cli: _Cli(),
        networks: await _loadedNetworks(api),
        selection: selection,
      );

      await controller.delete('grid-aaf6a46ced4f42f9');

      expect(selection.value.networkId, 'grid-e3b210eacc5b4cdf');
    });

    test('returns the refusal and does not touch the local list', () async {
      final api = _Api(deleteError: 'not the owner');
      final cli = _Cli();
      final controller = GridMutationsController(
        client: api,
        cli: cli,
        networks: await _loadedNetworks(api),
        selection: GridSelectionStore(storage: _MemoryStore()),
      );

      final error = await controller.delete('grid-e3b210eacc5b4cdf');

      expect(error, contains('not the owner'));
      expect(cli.ran, isEmpty);
      // Back to idle, so the row can be tried again — the message went to the
      // caller, which is the only place with somewhere to draw it.
      expect(controller.deleteState, isA<DeleteGridIdle>());
      expect(controller.isDeleting('grid-e3b210eacc5b4cdf'), isFalse);
    });

    // One row spins, not all of them.
    test('isDeleting names the grid in flight', () async {
      final api = _Api();
      final controller = GridMutationsController(
        client: api,
        cli: _Cli(),
        networks: await _loadedNetworks(api),
        selection: GridSelectionStore(storage: _MemoryStore()),
      );

      final pending = controller.delete('grid-aaf6a46ced4f42f9');
      expect(controller.isDeleting('grid-aaf6a46ced4f42f9'), isTrue);
      expect(controller.isDeleting('grid-e3b210eacc5b4cdf'), isFalse);
      await pending;
      expect(controller.isDeleting('grid-aaf6a46ced4f42f9'), isFalse);
    });
  });

  group('rename', () {
    // The fixture's owned grid.
    const owned = 'grid-aaf6a46ced4f42f9';

    test('calls the API, syncs, and reloads', () async {
      final api = _Api();
      final cli = _Cli();
      final controller = GridMutationsController(
        client: api,
        cli: cli,
        networks: await _loadedNetworks(api),
        selection: GridSelectionStore(storage: _MemoryStore()),
      );

      expect(await controller.rename(networkId: owned, name: '  hp-2  '), isNull);

      expect(api.renamed.single.id, owned);
      expect(api.renamed.single.name, 'hp-2');
      expect(cli.ran, [
        ['sync'],
      ]);
      expect(api.calls, 2);
      expect(controller.renameState, isA<RenameGridIdle>());
    });

    // The selection stores the NAME on disk so a reader can put the grid on
    // screen before anything is fetched. Left alone, the sidebar pill keeps
    // printing the retired name — across a relaunch, too.
    test('carries the new name into the saved selection', () async {
      final api = _Api();
      final storage = _MemoryStore();
      final selection = GridSelectionStore(storage: storage);
      await selection.selectNetwork(networkId: owned, networkName: 'hp-1-1');
      final controller = GridMutationsController(
        client: api,
        cli: _Cli(),
        networks: await _loadedNetworks(api),
        selection: selection,
      );

      await controller.rename(networkId: owned, name: 'hp-2');

      expect(selection.value.networkName, 'hp-2');
      expect(selection.value.networkId, owned, reason: 'the id never moves');
      expect(storage.values['grid_selected_network_name'], 'hp-2');
    });

    test('leaves a selection that named a different grid alone', () async {
      final api = _Api();
      final selection = GridSelectionStore(storage: _MemoryStore());
      await selection.selectNetwork(
        networkId: 'grid-e3b210eacc5b4cdf',
        networkName: 'Water Grid',
      );
      final controller = GridMutationsController(
        client: api,
        cli: _Cli(),
        networks: await _loadedNetworks(api),
        selection: selection,
      );

      await controller.rename(networkId: owned, name: 'hp-2');

      expect(selection.value.networkName, 'Water Grid');
    });

    // Renaming a grid to what it is already called is not a duplicate.
    test('does not compare a grid against its own name', () async {
      final api = _Api();
      final controller = GridMutationsController(
        client: api,
        cli: _Cli(),
        networks: await _loadedNetworks(api),
        selection: GridSelectionStore(storage: _MemoryStore()),
      );

      expect(
        await controller.rename(networkId: owned, name: 'hp-1-1'),
        isNull,
      );
      expect(api.renamed.single.name, 'hp-1-1');
    });

    test('refuses a name another grid already has', () async {
      final api = _Api();
      final cli = _Cli();
      final controller = GridMutationsController(
        client: api,
        cli: cli,
        networks: await _loadedNetworks(api),
        selection: GridSelectionStore(storage: _MemoryStore()),
      );

      final error = await controller.rename(
        networkId: owned,
        name: 'Water Grid',
      );

      expect(error, contains('already have a provider'));
      expect(api.renamed, isEmpty);
      expect(cli.ran, isEmpty);
      expect(controller.renameState, isA<RenameGridFailed>());
    });

    test('returns the control plane refusal', () async {
      final api = _Api(renameError: 'not the owner');
      final cli = _Cli();
      final controller = GridMutationsController(
        client: api,
        cli: cli,
        networks: await _loadedNetworks(api),
        selection: GridSelectionStore(storage: _MemoryStore()),
      );

      final error = await controller.rename(networkId: owned, name: 'hp-2');

      expect(error, contains('not the owner'));
      expect(cli.ran, isEmpty);
      expect(controller.renameState, isA<RenameGridFailed>());
    });
  });
}
