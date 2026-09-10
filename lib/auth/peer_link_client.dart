import 'cli_link.dart';

/// Linking to another machine by its remote password: `harness link connect/list/unlink` through
/// [CliLink], or the same exchange run by the app itself in a viewer build
/// (`viewer/direct_link.dart`).
abstract interface class PeerLinkClient {
  /// [onProgress] gets the CLI's stage names (`connecting`, `deriving_key`, `exchanging`,
  /// `verifying`) — best-effort feedback, never needed for correctness.
  Future<CliLinkConnectResult> connect(
    String machineId,
    String password, {
    void Function(String stage)? onProgress,
  });

  Future<CliLinkListResult> list();

  /// Null on success.
  Future<String?> unlink(String machineId);
}
