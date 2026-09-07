import 'dart:async';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'analytics.dart';
import 'analytics_client.dart';
import 'analytics_config.dart';
import 'analytics_event.dart';
import 'analytics_identity.dart';
import 'analytics_service.dart';

/// The app's one analytics sink.
///
/// A lazily-built singleton rather than a Riverpod provider, for the same
/// reason `themeModeStore` and `gridSelectionStore` are: the call sites have no
/// common ancestor short of `MaterialApp` — `main`, `AppNotifier`, a settings
/// pane, a menu item inside a pane header — and most of them are plain widgets
/// that were handed a notifier, not a `Ref`.
///
/// [NoopAnalytics] whenever tracking is off — no key in this build, the
/// environment muted it, the code is under `flutter test`, or the user opted
/// out in `~/.harness/desktop-app/analytics.json` — so a muted app and a test
/// run open no sockets at all rather than queueing into a void.
Analytics get analytics => _analytics ??= _build();

Analytics? _analytics;

/// Replaces the sink, for tests. Returns what was there, so a test can put it
/// back; passing null re-arms the lazy build.
@visibleForTesting
Analytics? setAnalyticsForTest(Analytics? value) {
  final previous = _analytics;
  _analytics = value;
  return previous;
}

Analytics _build() {
  // The environment is asked first, and on purpose: under `flutter test` this
  // returns before anything reads `~/.harness`, so a widget test that happens
  // to track an event touches neither the network nor a real Harness home.
  final config = AnalyticsConfig.resolve();
  if (!config.enabled) return const NoopAnalytics();
  final identity = AnalyticsIdentityStore();
  if (identity.optedOut) return const NoopAnalytics();
  return QueuedAnalytics(
    client: HttpAnalyticsClient(config),
    identityStore: identity,
    contextFuture: resolveAnalyticsContext(),
    userLookup: () => analyticsAccount.current,
  );
}

/// Who events are filed under.
///
/// `AppNotifier` writes it when sign-in resolves and clears it on sign-out; the
/// queue reads it fresh per event, so a visit that begins signed out and ends
/// signed in is not reported as anonymous throughout.
final AnalyticsAccount analyticsAccount = AnalyticsAccount();

/// The signed-in account, as the wire wants it. Mutable and global on purpose —
/// see [analyticsAccount].
class AnalyticsAccount {
  ({String? id, String? email}) current = (id: null, email: null);

  void set({String? id, String? email}) => current = (id: id, email: email);

  void clear() => current = (id: null, email: null);
}

/// The machine and build an event happened on, resolved once per launch.
///
/// Never fails: a version lookup that throws costs those fields, not the
/// stream. The queue awaits this once, before its first send, so the first
/// event of a launch already carries the version rather than racing it.
Future<AnalyticsContext> resolveAnalyticsContext() async {
  var version = '';
  var build = '';
  try {
    final info = await PackageInfo.fromPlatform();
    version = info.version;
    build = info.buildNumber;
  } on Object {
    // A bundle we can't read is worth an anonymous version, not a lost event.
  }
  return AnalyticsContext(
    platform: Platform.operatingSystem,
    appVersion: version,
    appBuild: build,
    osVersion: Platform.operatingSystemVersion,
    arch: Abi.current().toString(),
    locale: Platform.localeName,
    release: kReleaseMode,
  );
}
