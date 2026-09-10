import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/codex_profiles.dart';
import '../shared/widgets/app_select_field.dart';
import '../shared/widgets/labeled_field.dart';

/// Only mounted for this computer: a Mac path cannot select a remote account.
class CodexProfileField extends StatefulWidget {
  const CodexProfileField({
    super.key,
    required this.value,
    required this.onChanged,
    this.onBusyChanged,
    this.profiles,
    this.observedPaths = const {},
  });

  final LocalCodexProfile? value;
  final ValueChanged<LocalCodexProfile?> onChanged;
  final ValueChanged<bool>? onBusyChanged;
  final LocalCodexProfiles? profiles;
  final Set<String> observedPaths;

  @override
  State<CodexProfileField> createState() => _CodexProfileFieldState();
}

class _CodexProfileFieldState extends State<CodexProfileField> {
  late final _store = widget.profiles ?? LocalCodexProfiles();
  List<LocalCodexProfile> _profiles = const [];
  bool _loading = true;
  bool _linking = false;
  bool _hasChosenProfile = false;
  String? _error;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CodexProfileField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!setEquals(oldWidget.observedPaths, widget.observedPaths)) _load();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    // initState/didUpdateWidget can run during the parent's build. Report busy
    // after that build, before any user input can submit the default account.
    await Future<void>.value();
    if (!mounted || generation != _loadGeneration) return;
    _reportBusy();
    try {
      final loaded = await _store.load(observedPaths: widget.observedPaths);
      if (!mounted || generation != _loadGeneration) return;
      final profiles = {for (final profile in loaded) profile.path: profile}
          .values
          .toList();
      setState(() {
        _profiles = profiles;
        _loading = false;
      });
      if (profiles.length == 1 &&
          widget.value == null &&
          !_hasChosenProfile &&
          !_linking) {
        widget.onChanged(profiles.single);
      }
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = 'Could not refresh profiles. Try again or link a folder.';
      });
    } finally {
      if (mounted && generation == _loadGeneration) _reportBusy();
    }
  }

  void _reportBusy() => widget.onBusyChanged?.call(_loading || _linking);

  void _select(LocalCodexProfile? profile) {
    _hasChosenProfile = true;
    widget.onChanged(profile);
  }

  Future<void> _link() async {
    if (_linking) return;
    setState(() {
      _linking = true;
      _error = null;
    });
    _reportBusy();
    try {
      final path = await getDirectoryPath(
        initialDirectory: widget.value?.path,
        confirmButtonText: 'Link profile',
      );
      if (path == null || !mounted) return;
      final profile = await _store.link(path);
      if (!mounted) return;
      await _load();
      if (mounted) _select(profile);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not link this profile folder. Check that it is accessible.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _linking = false);
        _reportBusy();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Default is launch behavior, not another discovered account folder.
    final showPicker = _profiles.length >= 2;
    final remainingProfile = _profiles.length == 1 ? _profiles.single : null;
    final canChooseRemaining =
        !showPicker &&
        !_loading &&
        _error == null &&
        widget.value?.path != remainingProfile?.path;
    final choices = {
      for (final profile in _profiles) profile.path: profile,
      if (widget.value != null) widget.value!.path: widget.value!,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showPicker) ...[
          const FieldLabel('Codex profile'),
          AppSelectField<String>(
            key: const Key('new-agent-codex-profile-field'),
            value: widget.value?.path ?? '',
            options: [
              SelectOption(
                value: '',
                label: 'Default',
                note: _loading ? 'loading profiles…' : null,
                detail: 'Use this machine’s normal Codex launch.',
              ),
              for (final profile in choices.values)
                SelectOption(
                  value: profile.path,
                  label: profile.label,
                  detail: profile.path,
                ),
            ],
            onChanged: (value) => _select(choices[value]),
          ),
        ],
        if (canChooseRemaining)
          TextButton(
            onPressed: _linking ? null : () => _select(remainingProfile),
            child: Text(
              remainingProfile == null
                  ? 'Use default profile'
                  : 'Use ${remainingProfile.label}',
            ),
          ),
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _linking ? null : _link,
                  child: Text(
                    _linking ? 'Linking profile…' : 'Link a profile folder…',
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Refresh profiles',
              onPressed: _loading || _linking ? null : _load,
              icon: const Icon(LucideIcons.refreshCw, size: 14),
            ),
          ],
        ),
        Text(
          'Use the folder your Codex shortcut points to (CODEX_HOME).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}
