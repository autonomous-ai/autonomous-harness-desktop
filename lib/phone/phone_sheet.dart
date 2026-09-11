import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart';

/// One action in a phone sheet.
class PhoneSheetAction {
  const PhoneSheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;

  /// Run AFTER the sheet has closed — see [showPhoneSheet], which pops first and then calls this.
  /// A dialog opened from here would otherwise open behind the closing sheet.
  final VoidCallback onTap;

  final bool destructive;
}

/// The `⋯` menu on a phone page: a title line and a column of actions.
///
/// The desktop reaches the same actions through a right-click menu, which a phone has no gesture
/// for. One sheet rather than a menu per page: the actions differ, the shape does not.
Future<void> showPhoneSheet(
  BuildContext context, {
  required String title,
  required List<PhoneSheetAction> actions,
}) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  showDragHandle: true,
  backgroundColor: AppPalette.panelBg,
  builder: (sheetContext) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppPalette.textSecondary, fontSize: 13),
          ),
        ),
        for (final action in actions)
          _SheetRow(
            action: action,
            // Close first, then act: an action that opens a dialog or pushes a page must not do it
            // underneath a sheet that is still animating out.
            onTap: () {
              Navigator.of(sheetContext).pop();
              action.onTap();
            },
          ),
        const SizedBox(height: 8),
      ],
    ),
  ),
);

class _SheetRow extends StatelessWidget {
  const _SheetRow({required this.action, required this.onTap});

  final PhoneSheetAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final color = action.destructive
        ? AppPalette.dangerFill
        : AppPalette.textPrimary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            Icon(action.icon, size: 20, color: color),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                action.label,
                style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A yes/no question before something that cannot be undone — deleting an agent, unlinking a
/// machine. Returns true only if the destructive button was the one pressed.
Future<bool> confirmPhoneAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppPalette.panelBg,
      title: Text(
        title,
        style: TextStyle(color: AppPalette.textPrimary, fontSize: 18),
      ),
      content: Text(
        message,
        style: TextStyle(color: AppPalette.textSecondary, fontSize: 14),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppPalette.dangerFill),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
