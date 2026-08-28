import 'package:flutter/material.dart';

import '../state/app_state.dart';

class LoginScreen extends StatelessWidget {
  final AppNotifier notifier;
  const LoginScreen({super.key, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.memory, size: 56),
            const SizedBox(height: 12),
            const Text(
              'Harness',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: notifier.status == AppStatus.bootstrapping
                  ? null
                  : () => notifier.login(),
              icon: notifier.status == AppStatus.bootstrapping
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: const Text('Sign in'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Opens your browser to sign in via SSO.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (notifier.lastError != null) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Text(
                  'Error: ${notifier.lastError}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
