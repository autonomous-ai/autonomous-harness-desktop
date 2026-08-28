import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shown while `harness login --json` is waiting for the user to finish SSO in their system browser.
///
/// The SSO page itself can't be embedded in-app: auth.autonomous.ai's Google sign-in button uses
/// Google's popup-based Identity Services flow (a real popup window that posts the result back to its
/// opener), which the app's single-window embedded-browser model cannot satisfy. The system browser
/// handles this natively, so that's what actually opens; this screen just tracks the wait and returns
/// to the app automatically once `harness login --json` reports success (or lets the user cancel).
class AwaitingBrowserLoginScreen extends StatelessWidget {
  final VoidCallback onCancel;

  const AwaitingBrowserLoginScreen({super.key, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: 20),
            Text(
              'Continue in your browser',
              style: TextStyle(
                fontFamily: AppFonts.sans,
                fontFamilyFallback: AppFonts.sansFallback,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Finish signing in, then this window will continue on its own.',
              style: TextStyle(
                fontFamily: AppFonts.sans,
                fontFamilyFallback: AppFonts.sansFallback,
                fontSize: 11.2,
                color: AppColors.mutedStrong,
              ),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: onCancel,
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontFamily: AppFonts.sans,
                  fontFamilyFallback: AppFonts.sansFallback,
                  fontSize: 11.2,
                  color: AppColors.mutedStrong,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
