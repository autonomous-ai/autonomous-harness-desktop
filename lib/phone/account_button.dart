import 'dart:async';

import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart';
import '../state/app_state.dart';

/// Who is signed in, as a round initial in the corner of the machine list — and, on a tap, the
/// one account action a viewer has: signing out.
class AccountButton extends StatelessWidget {
  const AccountButton({super.key, required this.notifier});

  final AppNotifier notifier;

  String get _initial {
    final user = notifier.currentUser;
    final name = user?.name?.trim() ?? '';
    final source = name.isNotEmpty ? name : (user?.email ?? '');
    return source.isEmpty ? '?' : source.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Semantics(
      button: true,
      label: 'Account',
      child: GestureDetector(
        onTap: () => _showAccountSheet(context),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppPalette.avatarFill,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            _initial,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  void _showAccountSheet(BuildContext context) {
    final user = notifier.currentUser;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      backgroundColor: AppPalette.panelBg,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                user?.name ?? 'Signed in',
                style: TextStyle(
                  color: AppPalette.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                user?.email ?? '',
                style: TextStyle(color: AppPalette.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppPalette.dangerFill,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(notifier.logout());
                },
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
