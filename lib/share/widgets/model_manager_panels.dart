import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/theme/share_page_theme.dart';
import '../../shared/widgets/skeleton.dart';
import '../catalog_models.dart';
import '../local_models.dart';
import '../model_manager_controller.dart';
import '../pull_spec.dart';
import 'share_fields.dart';
import 'share_form_parts.dart';
import 'share_steps.dart';

/// The specs that download one version. Named here so the dialog and its test
/// agree on which field the URLs come from.
List<String> versionSpecs(ModelVersion version) =>
    versionPullSpecs(urls: version.urls, pullSpec: version.pullSpec);

/// The shelf: search, ranking, and what this Mac is told to prefer.
class CatalogList extends StatelessWidget {
  const CatalogList({
    super.key,
    required this.manager,
    required this.search,
    required this.busy,
  });

  final ModelManagerController manager;
  final TextEditingController search;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 16, 10),
          child: Column(
            children: [
              ShareTextField(
                controller: search,
                hint: 'Search the catalogue',
                onChanged: manager.search,
                leading: LucideIcons.search300,
              ),
              const SizedBox(height: 8),
              // A ranking only means something with nothing to rank against, so
              // it steps aside while there is a search term.
              if (manager.query.trim().isEmpty)
                // Wrapped, not a Row: three rankings do not fit a 372px rail at
                // every type size, and a chip cut in half reads as a bug.
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final sort in CatalogSort.values)
                        _SortChip(
                          label: sort.label,
                          selected: manager.sort == sort,
                          onTap: () => manager.setSort(sort),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: _rows()),
      ],
    );
  }

  Widget _rows() => switch (manager.state) {
    CatalogLoading() => const _CatalogSkeleton(key: Key('catalog-skeleton')),
    CatalogFailed(:final message) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ShareErrorNote(message: message),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: ShareLink(
              label: 'Try again',
              onPressed: manager.refreshList,
            ),
          ),
        ],
      ),
    ),
    CatalogReady(:final entries) => ListView(
      padding: const EdgeInsets.fromLTRB(14, 0, 10, 16),
      children: [
        // Kept above the shelf and never mixed into it: this is the only list
        // that was ranked against THIS machine's memory and chip.
        if (manager.recommended.isNotEmpty && manager.query.trim().isEmpty) ...[
          const _GroupLabel('PICKED FOR THIS MAC'),
          for (final entry in manager.recommended)
            _EntryRow(entry: entry, manager: manager, busy: busy),
          const SizedBox(height: 14),
          const _GroupLabel('THE CATALOGUE'),
        ],
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
            child: Text(
              manager.query.trim().isEmpty
                  ? 'The catalogue came back empty.'
                  : 'Nothing matches "${manager.query.trim()}".',
              style: ShareType.note,
            ),
          ),
        for (final entry in entries)
          _EntryRow(entry: entry, manager: manager, busy: busy),
      ],
    ),
  };
}

/// The shelf while the catalogue answers — and it answers often, because
/// every settled keystroke in the search field asks again.
///
/// A heading bar rather than "THE CATALOGUE" in ink: which group comes first
/// is part of the answer (the ranked picks only exist for an empty query), so
/// printing either name would be a claim. The rows under it wear the entry
/// row's padding at the entry row's two type sizes, fading down the rail.
class _CatalogSkeleton extends StatelessWidget {
  const _CatalogSkeleton({super.key});

  static const _rows = 6;
  static const _names = [0.56, 0.42, 0.64, 0.38, 0.52, 0.46];
  static const _notes = [0.8, 0.62, 0.72, 0.68, 0.58, 0.76];

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return SkeletonList(
      rows: _rows + 1,
      semanticsLabel: 'Loading the catalogue',
      padding: const EdgeInsets.fromLTRB(14, 0, 10, 16),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
            child: SkeletonText(style: ShareType.eyebrow, width: 118),
          );
        }
        final row = i - 1;
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SkeletonText(
                  style: ShareType.cardTitle,
                  widthFactor: _names[row % _names.length],
                ),
                const SizedBox(height: 3),
                SkeletonText(
                  style: ShareType.note,
                  widthFactor: _notes[row % _notes.length],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The quantisations of one model, before the catalogue has said what they
/// are: three [_VersionRow]-shaped plates, each with room for the label, its
/// size badge, the note and the Download button.
///
/// Three, because that is the low end of what a repo lists and the dialog is
/// capped: a skeleton taller than the answer jumps up when it lands.
class _VersionsSkeleton extends StatelessWidget {
  const _VersionsSkeleton({super.key});

  static const _labels = [72.0, 96.0, 84.0];

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final badgeHeight = SkeletonText.lineHeight(context, ShareType.badge) + 6;
    return SkeletonList(
      rows: 3,
      fadeDepth: skeletonFadeLight,
      semanticsLabel: 'Loading versions',
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(13, 11, 11, 11),
          decoration: BoxDecoration(
            color: SharePalette.fieldFill,
            border: Border.all(color: SharePalette.fieldRim),
            borderRadius: BorderRadius.circular(ShareMetrics.cardRadius),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        SkeletonText(
                          style: ShareType.cardTitle,
                          width: _labels[i],
                        ),
                        const SizedBox(width: 8),
                        Skeleton(
                          width: 44,
                          height: badgeHeight,
                          radius: ShareMetrics.badgeRadius,
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    SkeletonText(style: ShareType.note, widthFactor: 0.7),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Skeleton(width: 96, height: 32, radius: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
      child: Text(text, style: ShareType.eyebrow),
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected
                ? SharePalette.selectedFill
                : SharePalette.fieldFill,
            border: Border.all(
              color: selected
                  ? SharePalette.fieldRimHover
                  : SharePalette.fieldRim,
            ),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: selected ? grid.AppFont.semibold : FontWeight.w400,
              color: selected ? SharePalette.ink : SharePalette.labelInk,
            ),
          ),
        ),
      ),
    );
  }
}

/// One repo on the shelf.
class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.manager,
    required this.busy,
  });

  final CatalogEntry entry;
  final ModelManagerController manager;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final selected = manager.selectedRepo == entry.repoId;
    final installed = manager.isInstalled(entry.repoId, file: entry.file);
    final params = formatParams(entry.paramsB);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: busy ? null : () => manager.select(entry.repoId),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
            decoration: BoxDecoration(
              color: selected ? SharePalette.selectedFill : Colors.transparent,
              borderRadius: BorderRadius.circular(ShareMetrics.cardRadius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ShareType.cardTitle,
                      ),
                    ),
                    if (installed) ...[
                      const SizedBox(width: 8),
                      Icon(
                        LucideIcons.check300,
                        size: 14,
                        color: SharePalette.liveInk,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (entry.owner.isNotEmpty)
                      Flexible(
                        child: Text(
                          entry.owner,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ShareType.note,
                        ),
                      ),
                    if (params != null) _Dot(text: params),
                    if (entry.architecture != null)
                      _Dot(text: entry.architecture!),
                    if (entry.downloads > 0)
                      _Dot(text: '${formatCount(entry.downloads)} pulls'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Text('· $text', style: ShareType.note),
    );
  }
}

/// One model's quantisations, judged against this machine.
class VersionPanel extends StatelessWidget {
  const VersionPanel({
    super.key,
    required this.manager,
    required this.busy,
    required this.onDownload,
  });

  final ModelManagerController manager;
  final bool busy;
  final void Function(ModelVersion version, String repoId) onDownload;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final repoId = manager.selectedRepo!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(repoId, style: ShareType.cardTitle),
                    const SizedBox(height: 2),
                    Text('Pick a quantisation', style: ShareType.note),
                  ],
                ),
              ),
              ShareLink(
                label: 'On this disk →',
                onPressed: manager.closeDetail,
              ),
            ],
          ),
        ),
        Expanded(child: _body(repoId)),
      ],
    );
  }

  Widget _body(String repoId) {
    if (manager.detailLoading) {
      return const _VersionsSkeleton(key: Key('versions-skeleton'));
    }
    final error = manager.detailError;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: ShareErrorNote(message: error),
      );
    }
    final versions = manager.detail?.versions ?? const <ModelVersion>[];
    if (versions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Text(
          'The catalogue lists no downloadable file for this model.',
          style: ShareType.note,
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [
        for (final version in versions)
          _VersionRow(
            version: version,
            installed: manager.isInstalled(
              repoId,
              file: versionSpecs(version)
                  .map(pullSpecFileName)
                  .whereType<String>()
                  .firstOrNull,
            ),
            busy: busy,
            onDownload: () => onDownload(version, repoId),
          ),
      ],
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({
    required this.version,
    required this.installed,
    required this.busy,
    required this.onDownload,
  });

  final ModelVersion version;
  final bool installed;
  final bool busy;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final status = version.status;
    // Too large is the one verdict that disables the button: everything else is
    // a trade-off the reader is allowed to make, and a download they cannot run
    // is ten minutes and fifteen gigabytes spent on nothing.
    final blocked = status == VersionStatus.tooLarge;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 11, 11, 11),
        decoration: BoxDecoration(
          color: SharePalette.fieldFill,
          border: Border.all(color: SharePalette.fieldRim),
          borderRadius: BorderRadius.circular(ShareMetrics.cardRadius),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(version.label, style: ShareType.cardTitle),
                      const SizedBox(width: 8),
                      if (version.sizeBytes > 0)
                        ShareBadge(modelSizeLabel(version.sizeBytes)),
                    ],
                  ),
                  if (status != null || version.maxCtx != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (status != null) status.label,
                        if (version.maxCtx != null)
                          '${(version.maxCtx! / 1024).round()}k context',
                      ].join(' · '),
                      style: ShareType.note.copyWith(
                        color: blocked
                            ? SharePalette.danger
                            : status == VersionStatus.runnable
                            ? SharePalette.liveInk
                            : SharePalette.note,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (installed)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.check300,
                    size: 14,
                    color: SharePalette.liveInk,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'On this disk',
                    style: ShareType.note.copyWith(color: SharePalette.liveInk),
                  ),
                ],
              )
            else
              ShareButton(
                label: 'Download',
                icon: LucideIcons.download300,
                kind: ShareButtonKind.secondary,
                small: true,
                onPressed: busy || blocked ? null : onDownload,
              ),
          ],
        ),
      ),
    );
  }
}

/// What is already here, and how much of the disk it is holding.
class OnDiskPanel extends StatelessWidget {
  const OnDiskPanel({
    super.key,
    required this.manager,
    required this.onDelete,
    required this.busy,
  });

  final ModelManagerController manager;
  final void Function(LocalModel model) onDelete;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('On this disk', style: ShareType.cardTitle),
              const SizedBox(height: 2),
              Text(
                manager.local.isEmpty
                    ? 'Nothing downloaded yet. Pick a model on the left.'
                    : '${manager.local.length} '
                          '${manager.local.length == 1 ? 'model' : 'models'} · '
                          '${modelSizeLabel(manager.totalBytes)} used',
                style: ShareType.note,
              ),
            ],
          ),
        ),
        if (manager.deleteError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: ShareErrorNote(message: manager.deleteError!),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              for (final model in manager.local)
                _DiskRow(
                  model: model,
                  deleting: manager.deleting == model.file,
                  busy: busy,
                  onDelete: () => onDelete(model),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DiskRow extends StatelessWidget {
  const _DiskRow({
    required this.model,
    required this.deleting,
    required this.busy,
    required this.onDelete,
  });

  final LocalModel model;
  final bool deleting;
  final bool busy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final parts = model.expectedParts;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 11, 9, 11),
        decoration: BoxDecoration(
          color: SharePalette.fieldFill,
          border: Border.all(color: SharePalette.fieldRim),
          borderRadius: BorderRadius.circular(ShareMetrics.cardRadius),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ShareType.cardTitle,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      modelSizeLabel(model.sizeBytes),
                      if (parts != null)
                        model.isComplete
                            ? '$parts parts'
                            : 'Unfinished · ${model.parts} of $parts parts',
                    ].join(' · '),
                    style: ShareType.note.copyWith(
                      color: model.isComplete
                          ? SharePalette.note
                          : SharePalette.danger,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (deleting)
              const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              ShareGlyphButton(
                icon: LucideIcons.trash2300,
                tooltip: 'Delete from this disk',
                danger: true,
                onPressed: busy ? null : onDelete,
              ),
          ],
        ),
      ),
    );
  }
}
