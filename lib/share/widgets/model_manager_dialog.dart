import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/theme/share_page_theme.dart';
import '../catalog_models.dart';
import '../grid_cli.dart';
import '../local_models.dart';
import '../model_manager_controller.dart';
import '../model_pull.dart';
import 'share_fields.dart';
import 'share_form_parts.dart';
import 'model_manager_panels.dart';

/// "Download or manage models" — the shelf, and this computer's own.
///
/// A dialog rather than another route, because it is a detour: somebody is
/// setting a share up, finds they want a different model, and comes back to the
/// form they left. It also refuses to close on a tap outside — a download can
/// be running behind it, and losing that to a stray click is the worst thing
/// this screen could do.
Future<void> showModelManager(
  BuildContext context, {
  required ModelPullController pull,
  required VoidCallback onChanged,
  GridCli? cli,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) =>
      _ModelManagerDialog(pull: pull, onChanged: onChanged, cli: cli),
);

class _ModelManagerDialog extends StatefulWidget {
  const _ModelManagerDialog({
    required this.pull,
    required this.onChanged,
    this.cli,
  });

  final ModelPullController pull;

  /// Called whenever the models on disk change, so the form behind this dialog
  /// is never offering a model that has just been deleted.
  final VoidCallback onChanged;
  final GridCli? cli;

  @override
  State<_ModelManagerDialog> createState() => _ModelManagerDialogState();
}

class _ModelManagerDialogState extends State<_ModelManagerDialog> {
  late final ModelManagerController _manager = ModelManagerController(
    cli: widget.cli,
  );
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _manager.load();
  }

  @override
  void dispose() {
    _manager.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _download(ModelVersion version, String repoId) async {
    final specs = versionSpecs(version);
    if (specs.isEmpty) return;
    final ok = await widget.pull.pull(specs, label: _labelFor(version, repoId));
    if (!mounted) return;
    _manager.refreshLocal();
    widget.onChanged();
    if (ok) _manager.closeDetail();
  }

  Future<void> _delete(LocalModel model) async {
    await _manager.remove(model);
    if (!mounted) return;
    widget.onChanged();
  }

  String _labelFor(ModelVersion version, String repoId) {
    final tail = repoId.contains('/') ? repoId.split('/').last : repoId;
    return version.version == null ? tail : '$tail · ${version.label}';
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final screen = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: SharePalette.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: SharePalette.rim),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: screen.width < 1100 ? screen.width - 96 : 980,
          maxHeight: screen.height < 860 ? screen.height * 0.9 : 720,
        ),
        child: ListenableBuilder(
          listenable: Listenable.merge([_manager, widget.pull]),
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _Header(onClose: () => Navigator.of(context).pop()),
              if (widget.pull.isPulling || widget.pull.error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
                  child: PullBanner(pull: widget.pull),
                ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 372,
                      child: CatalogList(
                        manager: _manager,
                        search: _search,
                        busy: widget.pull.isPulling,
                      ),
                    ),
                    VerticalDivider(width: 1, color: SharePalette.innerRule),
                    Expanded(
                      child: _manager.selectedRepo == null
                          ? OnDiskPanel(
                              manager: _manager,
                              onDelete: _delete,
                              busy: widget.pull.isPulling,
                            )
                          : VersionPanel(
                              manager: _manager,
                              busy: widget.pull.isPulling,
                              onDownload: _download,
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 14, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Manage models', style: ShareType.paneTitle),
                const SizedBox(height: 3),
                Text(
                  'Everything the catalogue carries, and everything already on '
                  'this disk.',
                  style: ShareType.note,
                ),
              ],
            ),
          ),
          ShareGlyphButton(
            icon: LucideIcons.x300,
            size: 17,
            tooltip: 'Close',
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// A running download, over whichever half of the dialog is showing.
class PullBanner extends StatelessWidget {
  const PullBanner({super.key, required this.pull});

  final ModelPullController pull;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final error = pull.error;
    if (error != null && !pull.isPulling) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ShareErrorNote(message: error, onDismiss: pull.clearError),
      );
    }
    final progress = pull.progress;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(13, 11, 9, 12),
      decoration: BoxDecoration(
        color: SharePalette.fieldFill,
        border: Border.all(color: SharePalette.fieldRim),
        borderRadius: BorderRadius.circular(ShareMetrics.statusRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${pull.pulling}', style: ShareType.cardTitle),
              ),
              if (progress != null) ShareBadge(progress.label),
              const SizedBox(width: 6),
              TextButton(
                onPressed: pull.cancel,
                style: TextButton.styleFrom(
                  foregroundColor: SharePalette.helper,
                  minimumSize: const Size(0, 26),
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: const Text('Cancel'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              minHeight: 5,
              value: progress?.overall,
              backgroundColor: SharePalette.track,
              color: SharePalette.accent,
            ),
          ),
        ],
      ),
    );
  }
}
