import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../core/codex_profiles.dart';
import '../shared/widgets/app_select_field.dart';
import '../shared/widgets/labeled_field.dart';

/// Only mounted for this computer: a Mac path cannot select a remote account.
class CodexProfileField extends StatefulWidget {
  const CodexProfileField({
    super.key,
    required this.value,
    required this.onChanged,
    this.profiles,
  });

  final LocalCodexProfile? value;
  final ValueChanged<LocalCodexProfile?> onChanged;
  final LocalCodexProfiles? profiles;

  @override
  State<CodexProfileField> createState() => _CodexProfileFieldState();
}

class _CodexProfileFieldState extends State<CodexProfileField> {
  late final _store = widget.profiles ?? LocalCodexProfiles();
  List<LocalCodexProfile> _profiles = const [];
  bool _loading = true;
  bool _linking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profiles = await _store.load();
    if (!mounted) return;
    setState(() {
      _profiles = profiles;
      _loading = false;
    });
  }

  Future<void> _link() async {
    if (_linking) return;
    setState(() {
      _linking = true;
      _error = null;
    });
    try {
      final path = await getDirectoryPath(
        initialDirectory: widget.value?.path,
        confirmButtonText: 'Link profile',
      );
      if (path == null || !mounted) return;
      final profile = await _store.link(path);
      if (!mounted) return;
      await _load();
      if (mounted) widget.onChanged(profile);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not link this profile folder. Check that it is accessible.',
        );
      }
    } finally {
      if (mounted) setState(() => _linking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final choices = {
      for (final profile in _profiles) profile.path: profile,
      if (widget.value != null) widget.value!.path: widget.value!,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
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
          onChanged: (value) => widget.onChanged(choices[value]),
        ),
        TextButton(
          onPressed: _linking ? null : _link,
          child: Text(_linking ? 'Linking profile…' : 'Link a profile folder…'),
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
