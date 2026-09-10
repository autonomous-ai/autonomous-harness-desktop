import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/harness_file_store.dart';
import 'grid_surface.dart';

/// Which providers this computer is willing to use, persisted on its own.
///
/// **A separate file from `state.json`, deliberately.** Every other preference
/// in the app is a string under one shared document; this one is a *set* whose
/// membership is the whole point, and squeezing it into that store meant either
/// a comma-joined string nobody could read by eye or one key per provider,
/// which leaves an unbounded tail of dead keys behind every provider anyone
/// ever left. `~/.harness/desktop-app/providers_config.json` says what it holds
/// in its own name, and a person can open it.
///
/// ### Disabled is a CLIENT-side filter, not a fact about the grid
///
/// Turning a provider off changes nothing on the control plane: the grid keeps
/// running, this account stays a member, and anybody else's machine still sees
/// it. It means only "do not offer me this one" — the pickers
/// (`widgets/grid_target_pill.dart`, Settings ▸ Providers) skip it, which is
/// what makes an account on fifteen grids usable. That is why nothing here
/// calls the API, and why a provider that vanishes from `/v1/grid/me` needs no
/// cleanup: an id in this set that names no grid is inert.
///
/// ### The default is ON, and absence means ON
///
/// A provider this file has never heard of is enabled. The set therefore holds
/// only the **disabled** ids — the exceptions — so a fresh install with no file
/// at all behaves exactly like one where every switch was deliberately turned
/// on, and adding a grid elsewhere does not arrive switched off.
class ProviderEnablementStore extends ValueNotifier<Set<String>> {
  ProviderEnablementStore({
    @visibleForTesting File? file,
    // A compile-time const in the app; see [GridSelectionStore] for why a test
    // needs to pass the other value.
    @visibleForTesting this.gridSurface = kGridSurfaceEnabled,
  }) : _file = file,
       super(const <String>{});
  // ignore_for_file: prefer_initializing_formals

  static const fileName = 'providers_config.json';
  static const schemaVersion = 1;

  final File? _file;

  /// See the constructor: [kGridSurfaceEnabled], and only a test passes another.
  final bool gridSurface;

  File get file =>
      _file ??
      File(
        '${HarnessFileStore.defaultDirectoryPath()}'
        '${Platform.pathSeparator}$fileName',
      );

  /// The ids this computer has switched OFF. Everything else is on.
  Set<String> get disabledIds => value;

  /// Whether [networkId] may be offered. Unknown ids are on — see the class
  /// doc: the file records exceptions, not members.
  bool isEnabled(String networkId) => !value.contains(networkId);

  /// Read the saved set, if there is one.
  ///
  /// Failure is silent and lands on "nothing disabled", which is the same as a
  /// fresh install: an unreadable preferences file must not cost the user the
  /// providers they can reach. A build with the grid surface off reads nothing
  /// at all, for the reason `GridSelectionStore.load` gives — the file is
  /// shared with a debug build that can switch providers off, and a release
  /// build would otherwise hide providers behind a screen it does not draw.
  Future<void> load() async {
    if (!gridSurface) {
      value = const <String>{};
      return;
    }
    try {
      final target = file;
      if (!await target.exists()) {
        value = const <String>{};
        return;
      }
      final decoded = jsonDecode(await target.readAsString());
      if (decoded is! Map<String, dynamic>) {
        value = const <String>{};
        return;
      }
      final disabled = decoded['disabled'];
      value = disabled is List
          ? disabled.whereType<String>().where((id) => id.isNotEmpty).toSet()
          : const <String>{};
    } catch (_) {
      value = const <String>{};
    }
  }

  /// Turn a provider on or off.
  Future<void> setEnabled(String networkId, bool enabled) {
    final next = Set<String>.from(value);
    if (enabled) {
      next.remove(networkId);
    } else {
      next.add(networkId);
    }
    return _write(next);
  }

  /// Turn every provider back on.
  Future<void> enableAll() => _write(const <String>{});

  /// The notifier moves FIRST and the disk write is awaited after, so the
  /// switch animates on the click rather than on the filesystem — the same
  /// trade [GridSelectionStore] makes.
  Future<void> _write(Set<String> next) async {
    if (setEquals(value, next)) return;
    value = next;
    try {
      final target = file;
      await target.parent.create(recursive: true);
      final sorted = next.toList()..sort();
      await target.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert({'version': schemaVersion, 'disabled': sorted})}\n',
        flush: true,
      );
    } catch (_) {
      // Kept in memory for this run; see [load].
    }
  }
}

/// The one instance the app reads — a singleton for the reason
/// `gridSelectionStore` is one: the pickers that read it have no common
/// ancestor short of `MaterialApp`.
final providerEnablementStore = ProviderEnablementStore();
