import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/grid/grid_access.dart';
import 'package:harness/grid/grid_members_controller.dart';
import 'package:harness/grid/grid_network.dart';
import 'package:harness/grid/grid_networks_controller.dart';
import 'package:harness/grid/invite_email.dart';
import 'package:harness/grid/managed_network_member.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;
import 'package:harness/shared/widgets/member_avatar.dart';
import 'package:harness/widgets/share_grid/share_grid_dialog.dart';

import 'support/fake_grid_api.dart';
import 'support/real_fonts.dart';

/// The captured roster: 13 people somebody added and 20 admitted by the grid's
/// own email domain, one of the first group holding `admin`.
List<Map<String, dynamic>> _roster() => [
  for (final row
      in jsonDecode(File('test/fixtures/members.json').readAsStringSync())
          as List)
    Map<String, dynamic>.from(row as Map),
];

/// The member half of the control plane, answering from the fixture and
/// recording every write instead of making one.
class _Api extends FakeGridApi {
  _Api({this.refuse, List<Map<String, dynamic>>? rows})
    : rows = rows ?? _roster();

  /// What the server says no to, if anything.
  final String? refuse;

  List<Map<String, dynamic>> rows;
  final List<({String email, List<String> roles})> invites = [];
  final List<String> removals = [];

  @override
  Future<List<ManagedNetworkMember>> membersOrThrow(String networkId) async => [
    for (final row in rows) ManagedNetworkMember.fromJson(row),
  ];

  @override
  Future<void> addMember(
    String networkId, {
    required String email,
    required List<String> roles,
  }) async {
    if (refuse != null) throw Exception(refuse);
    invites.add((email: email, roles: roles));
    // The endpoint upserts, so a role change lands on the row already there.
    rows = [
      for (final row in rows)
        if (row['email'] != email) row,
      {'email': email, 'roles': roles, 'status': 'active', 'source': 'allowlist'},
    ];
  }

  @override
  Future<void> removeMember(String networkId, {required String email}) async {
    if (refuse != null) throw Exception(refuse);
    removals.add(email);
    rows = [
      for (final row in rows)
        if (row['email'] != email) row,
    ];
  }
}

GridNetwork _network({
  required String type,
  String name = 'autonomous.ai',
  String? accessDomain,
}) => GridNetwork(
  networkId: 'grid-1',
  name: name,
  ownerEmail: 'dev@autonomous.ai',
  networkType: type,
  status: 'active',
  routerEnabled: false,
  routerAdvisors: const [],
  accessDomain: accessDomain,
);

/// Pumps the sheet over the grid this account OWNS (`hp-1-1`, where the
/// membership is `admin`+`both`), unless [networkId] names the other one.
/// One row of each shape the sheet renders differently, so a count means
/// something. The 33-row capture drives the controller tests above; here the
/// list is capped at [SharePeopleList.maxHeight] and a count would be counting
/// the viewport.
List<Map<String, dynamic>> smallRoster() => [
  {
    'email': 'huy@example.com',
    'roles': ['admin', 'both'],
    'status': 'active',
    'source': 'allowlist',
  },
  {
    'email': 'kelvin@example.com',
    'roles': ['both'],
    'status': 'active',
    'source': 'allowlist',
  },
  {
    'email': 'design@example.com',
    'roles': ['both'],
    'status': 'active',
    'source': 'domain',
  },
  {
    'email': 'newcomer@example.com',
    'roles': ['consumer'],
    'status': 'pending',
    'source': 'allowlist',
  },
];

Future<void> _pumpSheet(
  WidgetTester tester, {
  required _Api api,
  String networkId = 'grid-aaf6a46ced4f42f9',
  String gridName = 'hp-1-1',
  VoidCallback? onChanged,
}) async {
  grid.AppTheme.brightness.value = Brightness.light;
  tester.view.physicalSize = const Size(1000, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final networks = GridNetworksController(client: api);
  addTearDown(networks.dispose);
  final members = GridMembersController(networkId: networkId, api: api);
  addTearDown(members.dispose);

  await tester.pumpWidget(
    MaterialApp(
      theme: grid.buildAppTheme(brightness: Brightness.light),
      home: ShareGridDialog(
        networkId: networkId,
        gridName: gridName,
        networks: networks,
        members: members,
        onChanged: onChanged,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the address a person actually types', () {
    test('says which half is broken, not just "invalid"', () {
      expect(inviteEmailError('dev@autonomous.ai'), isNull);
      expect(
        inviteEmailError('dev'),
        'An email address needs an @ — like teammate@example.com.',
      );
      expect(inviteEmailError('a@b@c.com'), contains('only have one @'));
      // Checked before the split, so a pasted address is not reported as a bad
      // local part and the user sent hunting in the wrong half.
      expect(inviteEmailError('dev @autonomous.ai'), contains("can't contain"));
      expect(inviteEmailError('dev@autonomous'), contains('needs a dot'));
      expect(inviteEmailError('dev@autonomous.4'), contains('real ending'));
      expect(inviteEmailError('dev@-autonomous.ai'), contains('characters'));
      expect(inviteEmailError(''), 'Enter an email address.');
    });

    test('accepts what SMTP does, and stops where SMTP stops', () {
      expect(inviteEmailError("o'brien+grid@sub.example.co.uk"), isNull);
      expect(inviteEmailError('${'a' * 65}@example.com'), contains('too long'));
      expect(inviteEmailError('..a@example.com'), contains('dot'));
    });
  });

  group('who can join', () {
    test('names the domain from the grid, which IS the domain', () {
      // The control plane refuses a `private-domain` grid named anything but
      // its domain, and `access_domain` comes back null on every network
      // `GET /v1/grid/me` returns — so the name is the field to read.
      final rule = gridAccessRule(_network(type: kNetworkTypePrivateDomain))!;
      expect(rule.label, '@autonomous.ai emails');
      expect(
        rule.description,
        'Anyone with an @autonomous.ai email can use this grid, or start an '
        'AI node to power it, as well as the people you invite.',
      );
    });

    test('prefers an explicit access_domain when the API sends one', () {
      final rule = gridAccessRule(
        _network(
          type: kNetworkTypePrivateDomain,
          name: 'grid-1',
          accessDomain: 'example.com',
        ),
      )!;
      expect(rule.label, '@example.com emails');
    });

    test('keeps both clauses on a grid whose consumers are open', () {
      // Opening up who may USE a grid is not opening up who may plug a machine
      // into it, and the first half alone reads as the larger promise.
      final rule = gridAccessRule(
        _network(type: kNetworkTypePermissionedProviders),
      )!;
      expect(rule.description, contains('Only the people above can start'));
    });

    test('says nothing at all about a rule it has no words for', () {
      // A sentence under this heading reads as a promise about who is already
      // in. Inventing one is the mistake nobody could catch.
      expect(gridAccessRule(_network(type: 'something-new')), isNull);
      expect(
        gridAccessRule(_network(type: kNetworkTypePrivateDomain, name: '  ')),
        isNull,
      );
    });

    test('an invite-only grid points at the list above it', () {
      for (final type in [
        kNetworkTypePermissioned,
        kNetworkTypePermissionedPublic,
      ]) {
        expect(gridAccessRule(_network(type: type))!.label, 'Invite only');
      }
    });
  });

  group('the roster', () {
    test('a refusal reaches the sheet, where the rail only drops a figure', () {
      // `members()` swallows so the rail can print nothing rather than a zero;
      // a dialog opened TO read the list has to say why it is empty.
      expect(
        GridMembersController(networkId: 'g', api: _Api()).loadError,
        isNull,
      );
    });

    test('an invite reloads the list, so the person lands in it', () async {
      final api = _Api();
      final members = GridMembersController(networkId: 'g', api: api);
      addTearDown(members.dispose);
      await members.refresh();
      expect(members.members, hasLength(33));

      expect(
        await members.invite(
          email: 'new@example.com',
          role: ManagedMemberRole.use,
        ),
        isNull,
      );
      expect(api.invites.single.roles, ['consumer']);
      expect(members.members, hasLength(34));
      expect(members.busy, isEmpty);
    });

    test('a refused write leaves the list alone and hands back the reason',
        () async {
      final members = GridMembersController(
        networkId: 'g',
        api: _Api(refuse: 'Seat limit reached'),
      );
      addTearDown(members.dispose);
      await members.refresh();

      final error = await members.remove('person13@example.com');
      expect(error, contains('Seat limit reached'));
      expect(members.members, hasLength(33));
      expect(members.busy, isEmpty);
    });
  });

  group('the sheet', () {
    setUpAll(loadRealFonts);

    testWidgets('names the grid, and each row by what it is', (tester) async {
      final api = _Api(rows: smallRoster());
      await _pumpSheet(tester, api: api);

      expect(find.text('Who can use “hp-1-1”'), findsOneWidget);
      expect(find.text('Invite people'), findsOneWidget);
      expect(find.text('Members'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);

      // The owner is a permanent member — the control plane won't remove them,
      // so they get a word rather than a control that can't work.
      expect(find.text('Owner'), findsOneWidget);
      // Grid has no name to print, so the second line says the one thing the
      // roster does know: whether this person has actually joined yet.
      expect(find.text('Invited — hasn’t joined yet'), findsOneWidget);
      // Two rows carry a menu: the owner's is a word, and the domain row has
      // nothing to remove and no grant to change.
      expect(find.text('Share a computer'), findsOneWidget);
      expect(find.text('Use models'), findsOneWidget);
    });

    testWidgets('the role and the send button wait for an address', (
      tester,
    ) async {
      final api = _Api(rows: smallRoster());
      await _pumpSheet(tester, api: api);

      // Docs' own behaviour, and what gives the address field its full width.
      expect(find.text('Invite'), findsNothing);
      await tester.enterText(find.byType(TextField), 'new@example.com');
      await tester.pumpAndSettle();
      expect(find.text('Invite'), findsOneWidget);
      // The widest grant leads — guessing narrower would silently withhold
      // something the inviter meant to give. One row already reads it, so the
      // picker makes two.
      expect(find.text('Share a computer'), findsNWidgets(2));
      expect(
        find.text(
          'They can use every model on this grid, and run one of their own '
          'computers for it.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a half-typed address is not scolded, a finished one is', (
      tester,
    ) async {
      final api = _Api(rows: smallRoster());
      await _pumpSheet(tester, api: api);

      await tester.enterText(find.byType(TextField), 'dev');
      await tester.pumpAndSettle();
      // Every half-typed address is invalid; complaining from keystroke one
      // sits there scolding somebody who is doing nothing wrong.
      expect(find.textContaining('needs an @'), findsNothing);

      await tester.tap(find.text('Invite'));
      await tester.pumpAndSettle();
      expect(find.textContaining('needs an @'), findsOneWidget);
      // And the request was never sent — the client already knew the answer.
      expect(api.invites, isEmpty);

      // Once it has spoken, the verdict follows every keystroke, so it goes the
      // instant the address becomes usable.
      await tester.enterText(find.byType(TextField), 'dev@example.com');
      await tester.pumpAndSettle();
      expect(find.textContaining('needs an @'), findsNothing);
    });

    testWidgets('inviting sends the grant, clears the field, keeps the sheet', (
      tester,
    ) async {
      final api = _Api(rows: smallRoster());
      var changed = 0;
      await _pumpSheet(tester, api: api, onChanged: () => changed++);

      await tester.enterText(find.byType(TextField), 'new@example.com');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Invite'));
      await tester.pumpAndSettle();

      expect(api.invites.single.email, 'new@example.com');
      expect(api.invites.single.roles, ['both']);
      expect(changed, 1);
      // The sheet stays open: the person lands in the list right below, which
      // is the whole reason the invite and the list share one surface.
      expect(find.text('Who can use “hp-1-1”'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    });

    testWidgets('a refusal is shown beside the field that caused it', (
      tester,
    ) async {
      final api = _Api(rows: smallRoster(), refuse: 'This grid has no seats');
      await _pumpSheet(tester, api: api);

      await tester.enterText(find.byType(TextField), 'new@example.com');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Invite'));
      await tester.pumpAndSettle();

      expect(find.textContaining('no seats'), findsOneWidget);
      // It was about the address that has just been sent, so editing clears it.
      await tester.enterText(find.byType(TextField), 'other@example.com');
      await tester.pumpAndSettle();
      expect(find.textContaining('no seats'), findsNothing);
    });

    testWidgets('a viewer who does not own the grid is offered no controls', (
      tester,
    ) async {
      // `Water Grid` is owned by someone else and this account holds `consumer`
      // on it. Removing cuts off a colleague who may be mid-task; ranking the
      // people already here is the owner's business.
      final api = _Api(rows: smallRoster());
      await _pumpSheet(
        tester,
        api: api,
        networkId: 'grid-e3b210eacc5b4cdf',
        gridName: 'Water Grid',
      );

      // The whole trailing column, not just Remove: a role somebody cannot
      // change is not a control, it is a wall of unclickable text beside the
      // names they came to read.
      expect(find.text('Share a computer'), findsNothing);
      expect(find.text('Owner'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'new@example.com');
      await tester.pumpAndSettle();
      // Never offer a grant they do not hold: the control plane refuses it
      // (403 `role_above_caller`), and a choice that 403s reads as a bug.
      expect(find.text('Use models'), findsOneWidget);
      expect(find.text('Share a computer'), findsNothing);
    });

    testWidgets('the owner can take a grant away, and change one', (
      tester,
    ) async {
      final api = _Api(rows: smallRoster());
      await _pumpSheet(tester, api: api);

      await tester.tap(find.text('Share a computer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove access'));
      await tester.pumpAndSettle();
      expect(api.removals, ['kelvin@example.com']);

      // A role change is ONE POST on the same endpoint the invite uses — the
      // store upserts. Not DELETE-then-POST, which drops the person off the
      // grid entirely if its second half fails.
      await tester.tap(find.text('Use models'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share a computer').last);
      await tester.pumpAndSettle();
      expect(api.invites.single.email, 'newcomer@example.com');
      expect(api.invites.single.roles, ['both']);
    });

    testWidgets('somebody here by email domain is offered no way off', (
      tester,
    ) async {
      // The control plane synthesises those rows: there is nothing to delete,
      // and every one of them holds the grant the RULE hands out — so the
      // column could only repeat what "Who can join" already said once.
      final api = _Api(rows: smallRoster());
      await _pumpSheet(tester, api: api);

      // The address is drawn in two spans — the half that differs in full ink,
      // the domain everyone shares behind it in a lighter one — but it is still
      // the whole address, because that is what a person copies.
      expect(find.text('design@example.com'), findsOneWidget);
      // Four rows, and only two of them carry a menu.
      expect(find.byType(MemberAvatar), findsNWidgets(4));
      expect(find.text('Share a computer'), findsOneWidget);
      expect(find.text('Use models'), findsOneWidget);
    });

    testWidgets('states the access rule, and offers no way to change it', (
      tester,
    ) async {
      // Grid's own sheet lets an owner flip this. Here it is a statement: the
      // flip restarts the grid under everyone on it, and every build of this
      // app currently shares one developer's Grid token.
      final api = _Api(rows: smallRoster());
      await _pumpSheet(tester, api: api);

      expect(find.text('Who can join'), findsOneWidget);
      expect(find.text('Invite only'), findsOneWidget);
      expect(
        find.text(
          'Only the people listed above can use this grid, or start an AI '
          'node to power it.',
        ),
        findsOneWidget,
      );
      expect(find.text('Save'), findsNothing);
    });
  });
}
