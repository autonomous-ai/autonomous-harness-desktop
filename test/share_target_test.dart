// Which grid this computer serves, now that it is no longer whichever one
// Settings ▸ Providers happens to point at.
//
// The precedence is a pure function and most of this file exercises it there:
// the widget can then be asked only about the thing a widget decides, which is
// what the page SAYS about the choice. That sentence is the feature as much as
// the picker is — somebody looking at `Water Grid` here has to be able to tell,
// without leaving the page, whether the agents they start moved with it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/grid/grid_network.dart';
import 'package:harness/grid/grid_networks_controller.dart';
import 'package:harness/grid/grid_selection_store.dart';
import 'package:harness/share/share_controller.dart';
import 'package:harness/share/share_route.dart';
import 'package:harness/share/share_target_store.dart';
import 'package:harness/share/widgets/share_fields.dart';
import 'package:harness/share/widgets/share_rail.dart';
import 'package:harness/share/widgets/share_target_picker.dart';

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

/// The office grid and the one this account only consumes from — see
/// `support/fake_grid_api.dart`.
const _officeId = 'grid-aaf6a46ced4f42f9';
const _officeName = 'hp-1-1';
const _waterId = 'grid-e3b210eacc5b4cdf';
const _waterName = 'Water Grid';

GridMe _me([Map<String, dynamic>? payload]) =>
    GridMe.fromJson(payload ?? Map<String, dynamic>.from(kGridMePayload));

GridNetworksState _ready([Map<String, dynamic>? payload]) =>
    GridNetworksReady(_me(payload));

/// [kGridMePayload] with both grids renamed to the same thing.
Map<String, dynamic> _sameNamePayload(String name) {
  final payload = Map<String, dynamic>.from(kGridMePayload);
  payload['networks'] = [
    for (final network in payload['networks']! as List)
      {...Map<String, dynamic>.from(network as Map), 'name': name},
  ];
  return payload;
}

Widget _picker({
  required ResolvedShareTarget target,
  String providersDefaultLabel = _officeName,
  GridNetworksState? state,
  ShareStatus status = ShareStatus.idle,
  void Function(String, String)? onPick,
  VoidCallback? onFollowDefault,
}) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      // The rail's real width, which is what the select measures its panel
      // against.
      width: 396,
      child: ShareTargetPicker(
        target: target,
        providersDefaultLabel: providersDefaultLabel,
        state: state ?? _ready(),
        status: status,
        onPick: onPick ?? (_, _) {},
        onFollowDefault: onFollowDefault ?? () {},
      ),
    ),
  ),
);

ResolvedShareTarget _following(String id, String name) =>
    ResolvedShareTarget(networkId: id, networkName: name, followsDefault: true);

ResolvedShareTarget _pinned(String id, String name) => ResolvedShareTarget(
  networkId: id,
  networkName: name,
  followsDefault: false,
);

void main() {
  group('resolveShareTarget', () {
    test('with nothing pinned, sharing follows the Providers default', () {
      final resolved = resolveShareTarget(
        ShareTarget.followDefault,
        const GridSelection(networkId: _officeId, networkName: _officeName),
      );
      expect(resolved.networkId, _officeId);
      expect(resolved.label, _officeName);
      expect(resolved.followsDefault, isTrue);
    });

    test('a pin wins, and does not move when the default does', () {
      const pin = ShareTarget(networkId: _waterId, networkName: _waterName);
      // The same pin against two different defaults. Pinning MEANS "whatever
      // that page says", so a pin that quietly tracked the default would be no
      // pin at all — and the page's whole promise is that the two are separate.
      for (final fallback in const [
        GridSelection(networkId: _officeId, networkName: _officeName),
        GridSelection(networkId: 'grid-later', networkName: 'somewhere else'),
        GridSelection.none,
      ]) {
        final resolved = resolveShareTarget(pin, fallback);
        expect(resolved.networkId, _waterId);
        expect(resolved.followsDefault, isFalse);
      }
    });

    test('no pin and no default is "nothing chosen", not a crash', () {
      final resolved = resolveShareTarget(
        ShareTarget.followDefault,
        GridSelection.none,
      );
      expect(resolved.hasGrid, isFalse);
      expect(resolved.followsDefault, isTrue);
    });

    test('a grid whose name was never learnt still prints as something', () {
      // The id is what a join needs; the name is only ever for the reader. A
      // pin carrying one and not the other must not render as a blank field.
      final resolved = resolveShareTarget(
        const ShareTarget(networkId: _waterId),
        GridSelection.none,
      );
      expect(resolved.label, _waterId);
    });
  });

  group('ShareTargetStore', () {
    test(
      'a machine that never touched the picker follows the default',
      () async {
        final store = ShareTargetStore(storage: _MemoryStore());
        await store.load();
        expect(store.value.isPinned, isFalse);
      },
    );

    test('a pin survives a relaunch', () async {
      final storage = _MemoryStore();
      await ShareTargetStore(storage: storage)
          .pin(networkId: _waterId, networkName: _waterName);

      final next = ShareTargetStore(storage: storage);
      await next.load();
      expect(next.value.networkId, _waterId);
      expect(next.value.networkName, _waterName);
    });

    test('following the default again leaves nothing behind on disk', () async {
      final storage = _MemoryStore();
      final store = ShareTargetStore(storage: storage);
      await store.pin(networkId: _waterId, networkName: _waterName);
      await store.followDefault();

      expect(store.value.isPinned, isFalse);
      // Not merely emptied: a key left holding "" would be read back by [load]
      // as an id, and the page would try to join a grid called nothing.
      expect(storage.values, isEmpty);
    });

    test('it writes under its own keys, never the selection\'s', () async {
      final storage = _MemoryStore();
      await ShareTargetStore(storage: storage)
          .pin(networkId: _waterId, networkName: _waterName);
      // The bug this closes would be invisible on screen and total in effect:
      // one key shared between the two stores is the coupling this whole
      // feature exists to break.
      expect(storage.values.keys, isNot(contains('grid_selected_network_id')));
      expect(
        storage.values.keys,
        isNot(contains('grid_selected_network_name')),
      );
    });

    test('a build without the grid surface reads no pin at all', () async {
      final storage = _MemoryStore();
      await ShareTargetStore(storage: storage)
          .pin(networkId: _waterId, networkName: _waterName);

      // `state.json` is shared with the debug build that CAN reach this picker.
      final shipped = ShareTargetStore(storage: storage, gridSurface: false);
      await shipped.load();
      expect(shipped.value.isPinned, isFalse);
    });
  });

  group('shareTargetOptions', () {
    test('a unique name is offered exactly as the user wrote it', () {
      final options = shareTargetOptions(_me().networks);
      expect(options.map((option) => option.label), [_officeName, _waterName]);
      expect(options.map((option) => option.networkId), [_officeId, _waterId]);
    });

    test('two grids with one name are told apart by their ids', () {
      final options = shareTargetOptions(
        _me(_sameNamePayload('research')).networks,
      );
      // Both rows are still findable, and neither is merely "research".
      expect(options.length, 2);
      expect(options.map((option) => option.label).toSet().length, 2);
      for (final option in options) {
        expect(option.label, startsWith('research · '));
      }
    });
  });

  group('shareTargetPlaceholder', () {
    test('every reason for an empty picker reads differently', () {
      final messages = {
        shareTargetPlaceholder(const GridNetworksIdle()),
        shareTargetPlaceholder(const GridNetworksLoading()),
        shareTargetPlaceholder(const GridNetworksSignedOut()),
        shareTargetPlaceholder(const GridNetworksFailed('token expired')),
        shareTargetPlaceholder(
          GridNetworksReady(_me({...kGridMePayload, 'networks': const []})),
        ),
      };
      // Idle and Loading deliberately share one — "we have not asked yet" and
      // "we are asking" are the same thing to a reader. The other three are the
      // ones that used to render identically and must not.
      expect(messages.length, 4);
      expect(messages, contains('token expired'));
    });

    test('an account with grids needs no placeholder', () {
      expect(shareTargetPlaceholder(_ready()), isNull);
    });
  });

  group('the sentence under the picker', () {
    testWidgets('following the default says where the agents are', (
      tester,
    ) async {
      await tester.pumpWidget(
        _picker(target: _following(_officeId, _officeName)),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Following the default in Settings'),
        findsOneWidget,
      );
      expect(find.textContaining('stay on $_officeName'), findsOneWidget);
      // Nothing to go back to: a reset on a page already in the default state
      // is a control whose only effect is to make the reader doubt themselves.
      expect(find.text('Follow the Providers default'), findsNothing);
    });

    testWidgets('a pin elsewhere names BOTH grids, and offers a way back', (
      tester,
    ) async {
      var followed = false;
      await tester.pumpWidget(
        _picker(
          target: _pinned(_waterId, _waterName),
          onFollowDefault: () => followed = true,
        ),
      );
      await tester.pumpAndSettle();

      // The confusing case, and the only one where the page has to say two
      // grid names in one breath: this computer serves one, the agents use the
      // other.
      expect(
        find.textContaining('This computer serves $_waterName'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Agents you start still use $_officeName'),
        findsOneWidget,
      );

      await tester.tap(find.text('Follow the Providers default'));
      expect(followed, isTrue);
    });

    testWidgets('pinning the default grid still reads as a pin', (
      tester,
    ) async {
      // Picking the grid that already IS the default is a real choice, not a
      // no-op: it says "stay here even if that page changes", and the sentence
      // has to be about that rather than about two names that are the same.
      await tester.pumpWidget(_picker(target: _pinned(_officeId, _officeName)));
      await tester.pumpAndSettle();

      expect(find.textContaining('Chosen here, not inherited'), findsOneWidget);
      expect(find.text('Follow the Providers default'), findsOneWidget);
    });

    testWidgets('a live share locks the picker and says why', (tester) async {
      await tester.pumpWidget(
        _picker(
          target: _following(_officeId, _officeName),
          status: ShareStatus.live,
        ),
      );
      await tester.pumpAndSettle();

      // Not a style choice: the engine is detached and joined to ONE grid, so
      // moving the picker under it would leave it serving a grid this page no
      // longer names — with no Stop button anywhere for it.
      final select = tester.widget<ShareSelect>(
        find.byKey(const Key('share-target-select')),
      );
      expect(select.enabled, isFalse);
      expect(find.textContaining('Stop sharing first'), findsOneWidget);
    });

    testWidgets('a pin naming a grid the account has left is called out', (
      tester,
    ) async {
      await tester.pumpWidget(
        _picker(target: _pinned('grid-long-gone', 'old lab')),
      );
      await tester.pumpAndSettle();

      // Left to the CLI this fails at the press, with a message about an id
      // nobody typed.
      expect(
        find.textContaining('not on your account any more'),
        findsOneWidget,
      );
      expect(find.text('Follow the Providers default'), findsOneWidget);
    });

    testWidgets('a fetch that has not landed accuses nobody of leaving', (
      tester,
    ) async {
      // The same pin, with the grid list still in flight. "You have left this
      // grid" is a statement about the account, and a pending request is not
      // evidence for it.
      await tester.pumpWidget(
        _picker(
          target: _pinned('grid-long-gone', 'old lab'),
          state: const GridNetworksLoading(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('not on your account any more'), findsNothing);
    });
  });

  testWidgets('the picker survives the rail it actually lives in', (
    tester,
  ) async {
    // The bug this closes shipped past every test above, because all of them
    // mount the picker on its own. The rail wraps its column in an
    // `IntrinsicHeight` — that is what lets a `Spacer` push the footnote to the
    // bottom of a scrolling column — and `ShareSelect` measures itself with a
    // `LayoutBuilder`, which cannot answer an intrinsic query. The result was
    // not a wobble: layout threw, and Share Intelligence rendered as a blank
    // pane. A widget is only proven by the tree it is used in.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            // The rail's real geometry, short enough that it has to scroll.
            width: 396,
            height: 600,
            child: ShareRail(
              gridName: _officeName,
              gridPicker: ShareTargetPicker(
                target: _following(_officeId, _officeName),
                providersDefaultLabel: _officeName,
                state: _ready(),
                status: ShareStatus.idle,
                onPick: (_, _) {},
                onFollowDefault: () {},
              ),
              offers: buildShareRouteOffers(
                canRunLocal: true,
                needsModel: false,
                keyProviders: const [],
                backends: const [],
              ),
              route: ShareRoute.local,
              status: ShareStatus.idle,
              onPick: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('GRID TO SHARE WITH'), findsOneWidget);
    // The footnote still gets pushed down, so the fix did not quietly cost the
    // layout the thing IntrinsicHeight was there for.
    expect(
      find.textContaining('closing Harness does not stop it'),
      findsOneWidget,
    );
  });

  testWidgets('picking a grid hands back the id, not just the label', (
    tester,
  ) async {
    String? pickedId;
    String? pickedName;
    await tester.pumpWidget(
      _picker(
        target: _following(_officeId, _officeName),
        onPick: (id, name) {
          pickedId = id;
          pickedName = name;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('share-target-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_waterName).last);
    await tester.pumpAndSettle();

    // A label is what the reader sees and an id is what `grid join` needs; the
    // two differ the moment two grids share a name.
    expect(pickedId, _waterId);
    expect(pickedName, _waterName);
  });
}
