import 'dart:io';

/// The name this computer joins a grid under — shown on the grid page, and the
/// stable engine id `grid join --name` / `grid leave --engine` match on.
///
/// Derived from the machine's own name so two computers do not both appear as a
/// generic "harness". Kept filesystem-safe because the CLI names each engine's
/// run record after it, and stable across restarts so a join made last week can
/// still be found and stopped. Never empty: the CLI replaces an empty `--name`
/// with a random `engine-<hex>`, which is a machine nobody can recognise on
/// their own grid page.
String deriveNodeName(String hostname) {
  final withoutLocal = hostname.trim().replaceFirst(
    RegExp(r'\.local$', caseSensitive: false),
    '',
  );
  final safe = withoutLocal
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-{2,}'), '-')
      .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
  return safe.isEmpty ? fallbackNodeName : safe;
}

/// Used when the host has no usable name, so a join never sends an empty one.
const String fallbackNodeName = 'harness-node';

/// This computer's name, ready to show in the field.
String get thisComputerName => deriveNodeName(Platform.localHostname);

/// Asks the OS for an unused loopback port by binding port 0 — the kernel hands
/// back a free ephemeral one — then releasing it.
///
/// Why not let the CLI use its own default: that default is 8081, a common port
/// another app on the machine may already hold, and the join then aborts with
/// "Port 8081 already in use". A tiny race remains between releasing this and
/// the engine binding it; losing it is reported as a start failure, and the
/// caller retries on a freshly picked port.
typedef FreePortFinder = Future<int> Function();

Future<int> findFreePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}
