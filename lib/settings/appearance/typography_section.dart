import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/theme/appearance_prefs_store.dart';
import '../../shared/widgets/app_select_field.dart';
import '../../shared/widgets/section_heading.dart';
import 'system_fonts.dart';

/// Settings ▸ Appearance ▸ Typography — the face the app is set in, and how big.
///
/// ⚠️ The APP's type, not the terminal's. The terminal keeps its own face and
/// size in Settings ▸ Terminal, because what it renders is a grid a remote
/// program draws into rather than a label this app writes — and the UI scale is
/// fenced out of it at five seams, guarded by
/// `test/terminal_ui_scale_isolation_test.dart`.
class TypographySection extends StatefulWidget {
  const TypographySection({super.key});

  @override
  State<TypographySection> createState() => _TypographySectionState();
}

class _TypographySectionState extends State<TypographySection> {
  /// ⚠️ Held in state, and re-made only when the SELECTED family moves.
  ///
  /// A `FutureBuilder` handed a future built inside `build` starts a new one on
  /// every rebuild, and each result rebuilds again — a loop that never settles.
  /// It costs nothing while the list is a constant and everything the day it
  /// crosses a MethodChannel, so it is written correctly now.
  late Future<List<SelectOption<String?>>> _families;
  String? _familiesFor;

  @override
  void initState() {
    super.initState();
    _familiesFor = appearancePrefsStore.value.uiFamily;
    _families = SystemFonts.load(selected: _familiesFor);
  }

  void _refreshFamilies(String? selected) {
    if (selected == _familiesFor) return;
    _familiesFor = selected;
    _families = SystemFonts.load(selected: selected);
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return ValueListenableBuilder<AppearancePrefs>(
      valueListenable: appearancePrefsStore,
      builder: (context, prefs, _) {
        _refreshFamilies(prefs.uiFamily);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeading(
              'Typography',
              subtitle:
                  'The face the app is set in, and how big. The terminal keeps '
                  'its own — see Terminal.',
            ),
            const SizedBox(height: 14),
            _SettingRow(
              title: 'UI font',
              detail: 'Every label, menu and heading in the app',
              control: FutureBuilder<List<SelectOption<String?>>>(
                future: _families,
                builder: (context, snapshot) {
                  final options = snapshot.data;
                  // Nothing to pick from yet: show the current value in a control
                  // of the right size rather than collapsing the row, so the
                  // column does not jump when the list arrives.
                  if (options == null) {
                    return const SizedBox(
                      width: _SettingRow.controlWidth,
                      height: grid.AppControl.height,
                    );
                  }
                  return AppSelectField<String?>(
                    width: _SettingRow.controlWidth,
                    value: prefs.uiFamily,
                    options: options,
                    onChanged: (family) =>
                        unawaited(appearancePrefsStore.setUiFamily(family)),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            _SettingRow(
              title: 'UI font size',
              detail: 'The base size everything else scales against',
              control: _SizeField(
                value: prefs.uiSize,
                onCommitted: (size) =>
                    unawaited(appearancePrefsStore.setUiSize(size)),
              ),
            ),
            const SizedBox(height: 14),
            const _TypePreview(),
          ],
        );
      },
    );
  }
}

/// One setting: a title and a line of detail on the left, its control on the
/// right.
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    required this.detail,
    required this.control,
  });

  final String title;
  final String detail;
  final Widget control;

  /// Fixed, so every control on this screen lines up on one right edge.
  static const double controlWidth = 188;

  /// Below this the control drops under the text and takes the full width.
  /// Squeezing it instead is what used to push it out past the row's own edge.
  static const double _stackBelow = controlWidth + 20 + 130;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 2),
        Text(detail, style: Theme.of(context).textTheme.bodySmall),
      ],
    );

    return Container(
      // A raised block: fill plus a soft lift, no rim. The same recipe the rest
      // of the app gives a row you can act on, so a setting here sits at the
      // same height as a row anywhere else.
      decoration: BoxDecoration(
        color: grid.AppGlass.surfaceFill,
        borderRadius: BorderRadius.circular(14),
        boxShadow: grid.AppGlass.cardShadow,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth < _stackBelow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [text, const SizedBox(height: 10), control],
              )
            : Row(
                children: [
                  Expanded(child: text),
                  const SizedBox(width: 20),
                  control,
                ],
              ),
      ),
    );
  }
}

/// The size box: a number, right-aligned, with its unit inside the field.
///
/// ⚠️ Commits on Enter and on losing focus, NEVER on each keystroke. Typing the
/// `9` on the way to `19` would resize the whole app for a moment — including
/// this very field, under the caret that is typing into it.
class _SizeField extends StatefulWidget {
  const _SizeField({required this.value, required this.onCommitted});

  final double value;
  final ValueChanged<double> onCommitted;

  @override
  State<_SizeField> createState() => _SizeFieldState();
}

class _SizeFieldState extends State<_SizeField> {
  late final TextEditingController _controller = TextEditingController(
    text: _format(widget.value),
  );
  late final FocusNode _focus = FocusNode()..addListener(_onFocusChange);

  static String _format(double value) =>
      value == value.roundToDouble() ? value.round().toString() : '$value';

  @override
  void didUpdateWidget(covariant _SizeField old) {
    super.didUpdateWidget(old);
    // Follow the store when the change came from somewhere else (a reset), but
    // never yank the text out from under someone mid-edit.
    if (widget.value != old.value && !_focus.hasFocus) {
      _controller.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    final parsed = double.tryParse(_controller.text.trim());
    if (parsed == null || !parsed.isFinite) {
      // ⚠️ Revert, do not reset. Unparseable input is a typo, and answering a
      // typo by silently discarding the user's actual setting is a bigger
      // surprise than doing nothing.
      _controller.text = _format(widget.value);
      return;
    }
    final clamped = parsed.clamp(
      AppearancePrefs.uiSizeMin,
      AppearancePrefs.uiSizeMax,
    );
    // Snapped values are written BACK into the field, so it never shows a number
    // the app is not actually using.
    _controller.text = _format(clamped);
    if (clamped != widget.value) widget.onCommitted(clamped);
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return SizedBox(
      width: 96,
      child: TextField(
        key: const Key('appearance-ui-size-field'),
        controller: _controller,
        focusNode: _focus,
        textAlign: TextAlign.right,
        style: grid.kFieldTextStyle,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        onSubmitted: (_) => _commit(),
        decoration: const InputDecoration(
          // Inside the field, not after it: a unit hung outside would push the
          // box off the right edge the other controls line up on.
          suffixText: 'px',
          isDense: true,
        ),
      ),
    );
  }
}

/// What the choices above actually look like.
///
/// One line of prose at the app's own body size — which is the shape of nearly
/// every surface in this app, so the sample is the thing rather than a stand-in
/// for it. It scales with the setting because it is app chrome, and that is the
/// whole point of showing it.
class _TypePreview extends StatelessWidget {
  const _TypePreview();

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: grid.AppGlass.surfaceFill,
        borderRadius: BorderRadius.circular(14),
        boxShadow: grid.AppGlass.cardShadow,
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Preview', style: theme.textTheme.titleSmall),
          const SizedBox(height: 10),
          Text(
            'Machines and the agents on them.',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'This is how a line of the app reads at the size you picked — a '
            'heading above it, and the quieter line that explains one.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Secondary copy, the way a row subtitle is set.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
