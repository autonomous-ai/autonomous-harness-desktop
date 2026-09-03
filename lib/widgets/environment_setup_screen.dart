import 'package:flutter/material.dart';

import '../bootstrap/environment_provisioner.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../shared/theme/app_theme.dart' as grid;

/// First-run bootstrap surface. Provisioning starts without a confirmation
/// dialog; this screen makes every system-affecting step visible and gives the
/// user a retry path only when macOS requires an interactive Terminal action.
class EnvironmentSetupScreen extends StatelessWidget {
  final AppNotifier notifier;

  const EnvironmentSetupScreen({super.key, required this.notifier});

  @override
  Widget build(BuildContext context) {
    final readiness = notifier.environmentReadiness;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            color: AppColors.surface,
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Preparing this Mac',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    readiness.message ?? 'Checking the environment…',
                    style: TextStyle(color: AppColors.mutedStrong),
                  ),
                  const SizedBox(height: 22),
                  for (final step in EnvironmentStep.values)
                    _StepRow(step: step, status: readiness.steps[step]!),
                  if (readiness.output.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 150),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(
                          grid.AppCard.insetRadius,
                        ),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          readiness.output.join('\n'),
                          style: TextStyle(
                            fontFamily: AppFonts.mono,
                            fontSize: 11,
                            color: AppColors.mutedStrong,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (readiness.needsTerminal ||
                      readiness.steps.values.contains(
                        EnvironmentStepStatus.failed,
                      )) ...[
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: notifier.retryEnvironmentSetup,
                      icon: const Icon(Icons.refresh),
                      label: Text(
                        readiness.needsTerminal ? 'Retry after setup' : 'Retry',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final EnvironmentStep step;
  final EnvironmentStepStatus status;

  const _StepRow({required this.step, required this.status});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      EnvironmentStepStatus.pending => (Icons.circle_outlined, AppColors.muted),
      EnvironmentStepStatus.running => (Icons.sync, AppColors.accent),
      EnvironmentStepStatus.ready => (Icons.check_circle, AppColors.success),
      EnvironmentStepStatus.needsTerminal => (
        Icons.terminal,
        AppColors.warning,
      ),
      EnvironmentStepStatus.failed => (Icons.error_outline, AppColors.danger),
    };
    final label = switch (step) {
      EnvironmentStep.node => 'Managed Node runtime',
      EnvironmentStep.harness => 'Harness CLI',
      EnvironmentStep.tmux => 'tmux terminal support',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          status == EnvironmentStepStatus.running
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          Text(switch (status) {
            EnvironmentStepStatus.pending => 'Waiting',
            EnvironmentStepStatus.running => 'Working',
            EnvironmentStepStatus.ready => 'Ready',
            EnvironmentStepStatus.needsTerminal => 'Terminal needed',
            EnvironmentStepStatus.failed => 'Failed',
          }, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}
