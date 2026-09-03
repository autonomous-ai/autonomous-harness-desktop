import 'dart:async';

import 'package:flutter/foundation.dart';

import '../grid/grid_api_client.dart';
import 'catalog_models.dart';
import 'grid_cli.dart';
import 'local_models.dart';
import 'pull_spec.dart';

/// How the catalogue is ranked when nobody is searching.
enum CatalogSort {
  trending('trending', 'Trending'),
  likes('likes', 'Most liked'),
  created('created_at', 'Newest');

  const CatalogSort(this.wire, this.label);

  final String wire;
  final String label;
}

/// The state of one list request.
sealed class CatalogState {
  const CatalogState();
}

class CatalogLoading extends CatalogState {
  const CatalogLoading();
}

class CatalogFailed extends CatalogState {
  const CatalogFailed(this.message);

  final String message;
}

class CatalogReady extends CatalogState {
  const CatalogReady(this.entries);

  final List<CatalogEntry> entries;
}

/// Everything the Manage models screen knows.
///
/// It reads from **both** catalogues on purpose, because they answer different
/// questions. `grid catalog` knows this Mac — it ranks a couple of picks
/// against its actual memory and chip — and the control plane knows the shelf.
/// Showing only the first is the version this replaces, and on a machine that
/// already had its one recommendation it said "nothing left to download",
/// which was true of that list and plainly untrue of the world.
class ModelManagerController extends ChangeNotifier {
  ModelManagerController({GridCli? cli, GridApiClient? api})
    : _cli = cli ?? GridCli(),
      _api = api ?? GridApiClient();

  final GridCli _cli;
  final GridApiClient _api;

  CatalogState state = const CatalogLoading();
  CatalogSort sort = CatalogSort.trending;
  String query = '';

  /// The repo whose versions are open, and what came back for it.
  String? selectedRepo;
  ModelDetail? detail;
  bool detailLoading = false;
  String? detailError;

  /// What `grid catalog` recommends for this exact machine, which the shelf
  /// cannot know. Shown first, and never mixed into the search results.
  List<CatalogEntry> recommended = const [];

  /// What is on disk right now.
  List<LocalModel> local = const [];

  /// The file being deleted, so its row can say so.
  String? deleting;
  String? deleteError;

  Map<String, dynamic>? _device;
  bool _disposed = false;
  int _listRequest = 0;
  Timer? _debounce;

  Set<String> get localFileNames => {for (final model in local) model.file};

  int get totalBytes =>
      local.fold(0, (sum, model) => sum + model.sizeBytes);

  /// Read the disk, this machine's profile and the shelf, in that order of
  /// certainty. Only the last of the three can fail in a way worth a message.
  Future<void> load() async {
    local = readLocalModels();
    _notify();
    await Future.wait([_loadDevice(), _loadRecommended()]);
    await refreshList();
  }

  /// Re-read what is on disk. Called after a download or a delete, and cheap —
  /// it is a directory listing.
  void refreshLocal() {
    local = readLocalModels();
    _notify();
  }

  Future<void> _loadDevice() async {
    // Without it the versions arrive unjudged, which is worse than judged and
    // far better than nothing.
    _device = await _cli.runJson<Map<String, dynamic>>(['device-info']);
  }

  Future<void> _loadRecommended() async {
    final rows = await _cli.runJson<List<dynamic>>(['catalog']);
    recommended = [
      for (final row in rows ?? const [])
        if (row is Map && row['hf_repo'] is String)
          CatalogEntry(
            repoId: row['hf_repo'] as String,
            downloads: 0,
            likes: 0,
            format: 'GGUF',
            file: row['file'] as String?,
          ),
    ];
    _notify();
  }

  /// Search as the user types, one request behind them rather than one per
  /// keystroke — the catalogue is a network call and a 12-character model name
  /// is twelve of them.
  void search(String value) {
    query = value;
    _notify();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), refreshList);
  }

  void setSort(CatalogSort value) {
    if (sort == value) return;
    sort = value;
    _notify();
    unawaited(refreshList());
  }

  Future<void> refreshList() async {
    final request = ++_listRequest;
    state = const CatalogLoading();
    _notify();
    try {
      final entries = await _api.catalog(
        // A ranking is only pinned once there is nothing to rank against: with
        // a search term the server's own relevance is the better order.
        sort: query.trim().isEmpty ? sort.wire : null,
        query: query,
      );
      if (request != _listRequest) return;
      state = CatalogReady(entries);
    } on Object catch (error) {
      if (request != _listRequest) return;
      state = CatalogFailed(_message(error));
    }
    _notify();
  }

  /// Open one model's versions.
  Future<void> select(String repoId) async {
    selectedRepo = repoId;
    detail = null;
    detailError = null;
    detailLoading = true;
    _notify();
    try {
      final loaded = await _api.catalogDetail(repoId, device: _device);
      if (selectedRepo != repoId) return;
      detail = loaded;
    } on Object catch (error) {
      if (selectedRepo != repoId) return;
      detailError = _message(error);
    }
    detailLoading = false;
    _notify();
  }

  void closeDetail() {
    selectedRepo = null;
    detail = null;
    detailError = null;
    _notify();
  }

  /// Is this repo already on disk, in any quantisation?
  bool isInstalled(String repoId, {String? file}) => isCatalogModelInstalled(
    repoId: repoId,
    file: file,
    localFileNames: localFileNames,
  );

  /// Delete one GGUF, and every shard of it when it is a split set.
  ///
  /// `grid rm` takes one filename, so a five-part model is five commands. The
  /// first failure stops it and says so — silently leaving four shards behind
  /// would report freed space that was never freed.
  Future<void> remove(LocalModel model) async {
    deleting = model.file;
    deleteError = null;
    _notify();
    for (final file in filesOf(model)) {
      final result = await _cli.run(['rm', file, '--yes']);
      if (!result.ok) {
        deleteError = result.errorMessage;
        break;
      }
    }
    deleting = null;
    refreshLocal();
  }

  /// Every file backing [model]: the shards of a split set, or the one file.
  ///
  /// Derived from the shard marker rather than by re-listing the directory —
  /// `-00002-of-00005.gguf` says exactly what its siblings are called, and a
  /// second listing would only reintroduce the question of which of them belong
  /// to this model.
  static List<String> filesOf(LocalModel model) {
    final match = RegExp(
      r'^(.*)-(\d+)-of-(\d+)\.gguf$',
      caseSensitive: false,
    ).firstMatch(model.file);
    if (match == null) return [model.file];
    final stem = match.group(1)!;
    final width = match.group(2)!.length;
    final total = match.group(3)!;
    return [
      for (var part = 1; part <= int.parse(total); part++)
        '$stem-${part.toString().padLeft(width, '0')}-of-$total.gguf',
    ];
  }

  static String _message(Object error) {
    final text = '$error';
    // Dio and ApiException both carry a readable sentence; a raw exception dump
    // in a dialog is a wall nobody can act on.
    return text.length > 160 ? '${text.substring(0, 157)}…' : text;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }
}
