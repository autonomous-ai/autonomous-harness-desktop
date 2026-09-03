import 'package:flutter/foundation.dart';

import 'grid_api_client.dart';
import 'managed_network_member.dart';

/// Everyone on one grid, and the three things the share sheet does to that
/// list: invite somebody, change what somebody may do, take somebody off.
///
/// Owned by the sheet and disposed with it — unlike [GridOverviewController],
/// which polls for the whole app. The roster it holds is the same one the rail
/// reads, fetched again here rather than shared, because the two ask different
/// questions of the same endpoint: the rail wants a count and treats a refusal
/// as "no figure", while this dialog was opened to read the list and has to say
/// why it cannot.
class GridMembersController extends ChangeNotifier {
  GridMembersController({required this.networkId, GridApiClient? api})
    : _api = api ?? GridApiClient();

  final String networkId;
  final GridApiClient _api;

  /// The roster, or null before the first answer lands.
  List<ManagedNetworkMember>? members;

  /// Why the roster is not here. Null while it is, or while it is still coming.
  String? loadError;

  /// The first load has not landed. Distinct from `members == null` after a
  /// failure: one draws skeleton rows, the other a sentence.
  bool loading = false;

  /// Addresses with a write in flight, so each row spins on its own rather than
  /// the whole list going blank.
  final Set<String> busy = {};

  bool _disposed = false;

  /// Loads once. Cheap to call from `build` — only the first call does anything.
  void ensureLoaded() {
    if (members == null && loadError == null && !loading) refresh();
  }

  Future<void> refresh() async {
    loading = members == null;
    _notify();
    try {
      members = await _api.membersOrThrow(networkId);
      loadError = null;
    } catch (error) {
      // Keep whatever is on screen: a roster that arrived a moment ago has not
      // stopped being true because a refresh after an invite timed out.
      if (members == null) loadError = '$error';
    }
    loading = false;
    _notify();
  }

  /// Invites [email], or — the same call — changes the grant they already hold.
  ///
  /// Returns null on success and a user-facing sentence otherwise, rather than
  /// throwing: every caller has somewhere to put the message, and none of them
  /// wants an exception crossing a button press.
  ///
  /// The roster is reloaded on success, which is what puts the person in the
  /// list under the field that invited them.
  Future<String?> invite({
    required String email,
    required ManagedMemberRole role,
  }) => _write(email, () => _api.addMember(
    networkId,
    email: email,
    roles: [role.wire],
  ));

  Future<String?> remove(String email) =>
      _write(email, () => _api.removeMember(networkId, email: email));

  /// One write, with this address marked busy for its duration and the roster
  /// reloaded after it lands.
  Future<String?> _write(String email, Future<void> Function() call) async {
    busy.add(email);
    _notify();
    String? failure;
    try {
      await call();
    } catch (error) {
      failure = '$error';
    }
    busy.remove(email);
    _notify();
    if (failure == null) await refresh();
    return failure;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
