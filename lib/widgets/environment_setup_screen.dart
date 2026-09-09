import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bootstrap/environment_provisioner.dart';
import '../bootstrap/environment_step_guidance.dart';
import '../shared/widgets/command_row.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../shared/theme/app_theme.dart' as grid;

/// First-run bootstrap surface. Provisioning starts without a confirmation
/// dialog; this screen makes every system-affecting step visible. The happy
/// path needs nothing from the user — this screen's only real job is the
/// case the app cannot fully automate: a step stuck in `needsTerminal` (a
/// package-manager install needs a real tty) or `failed`. For those, each
/// step shows the exact command to run and its own Recheck button, so fixing
/// one step never disturbs the others — see `environment_step_guidance.dart`.
class EnvironmentSetupScreen extends StatefulWidget {
  final AppNotifier notifier;

  const EnvironmentSetupScreen({super.key, required this.notifier});

  @override
  State<EnvironmentSetupScreen> createState() => _EnvironmentSetupScreenState();
}

class _EnvironmentSetupScreenState extends State<EnvironmentSetupScreen> {
  String? _copiedCommand;

  Future<void> _copy(String command) async {
    await Clipboard.setData(ClipboardData(text: command));
    if (!mounted) return;
    setState(() => _copiedCommand = command);
    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      if (mounted && _copiedCommand == command) {
        setState(() => _copiedCommand = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final notifier = widget.notifier;
    final readiness = notifier.environmentReadiness;
    final busy = notifier.environmentSetupInFlight;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            color: AppColors.surface,
            // A stuck step's guidance block (command + Recheck) can push this well past a short
            // window's height — bounded + scrollable so it never overflows, but still shrink-wraps
            // to its content (rather than always filling the window) when everything fits.
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.85,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Preparing this computer',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      readiness.message ?? 'Checking the environment…',
                      style: TextStyle(color: AppColors.mutedStrong),
                    ),
                    const SizedBox(height: 22),
                    for (final step in EnvironmentStep.values)
                      _StepRow(
                        step: step,
                        status: readiness.steps[step]!,
                        busy: busy,
                        recheckPending: notifier.environmentRecheckPending,
                        copiedCommand: _copiedCommand,
                        onCopy: _copy,
                        onRecheck: () => notifier.recheckEnvironmentStep(step),
                      ),
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
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: busy ? null : notifier.retryEnvironmentSetup,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Start over'),
                      ),
                    ),
                  ],
                ),
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
  final bool busy;
  final bool recheckPending;
  final String? copiedCommand;
  final void Function(String command) onCopy;
  final VoidCallback onRecheck;

  const _StepRow({
    required this.step,
    required this.status,
    required this.busy,
    required this.recheckPending,
    required this.copiedCommand,
    required this.onCopy,
    required this.onRecheck,
  });

  bool get _stuck =>
      status == EnvironmentStepStatus.failed ||
      status == EnvironmentStepStatus.needsTerminal;

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
      EnvironmentStepStatus.unavailable => (
        Icons.remove_circle_outline,
        AppColors.muted,
      ),
    };
    final label = switch (step) {
      // One step, and it owns the CLI AND the Node it runs on: install.sh brings
      // its own runtime, so there is nothing separate left to show.
      EnvironmentStep.harness => 'Harness CLI & runtime',
      EnvironmentStep.tmux => 'tmux terminal support',
      EnvironmentStep.grid => 'Grid CLI for sharing this computer',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                EnvironmentStepStatus.unavailable => 'Not installed',
              }, style: TextStyle(fontSize: 12, color: color)),
            ],
          ),
          if (_stuck)
            _StepGuidance(
              step: step,
              status: status,
              busy: busy,
              recheckPending: recheckPending,
              copiedCommand: copiedCommand,
              onCopy: onCopy,
              onRecheck: onRecheck,
            ),
        ],
      ),
    );
  }
}

/// The command block + Recheck button shown under a stuck step's row.
class _StepGuidance extends StatelessWidget {
  final EnvironmentStep step;
  final EnvironmentStepStatus status;
  final bool busy;
  final bool recheckPending;
  final String? copiedCommand;
  final void Function(String command) onCopy;
  final VoidCallback onRecheck;

  const _StepGuidance({
    required this.step,
    required this.status,
    required this.busy,
    required this.recheckPending,
    required this.copiedCommand,
    required this.onCopy,
    required this.onRecheck,
  });

  @override
  Widget build(BuildContext context) {
    final isMacOS = Platform.isMacOS;
    final text = environmentStepGuidanceText(step, status, isMacOS: isMacOS);
    final command = environmentStepGuidanceCommand(
      step,
      status,
      isMacOS: isMacOS,
    );
    return Container(
      margin: const EdgeInsets.only(left: 28, top: 8, bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(grid.AppCard.insetRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (text.isNotEmpty)
            Text(
              text,
              style: TextStyle(color: AppColors.textSoft, height: 1.4),
            ),
          if (command != null) ...[
            const SizedBox(height: 10),
            CommandRow(
              command: command,
              copied: copiedCommand == command,
              onCopy: () => onCopy(command),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (recheckPending) ...[
                const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Checking automatically every 5s…',
                    style: TextStyle(
                      color: AppColors.mutedStrong,
                      fontSize: 12,
                    ),
                  ),
                ),
              ] else
                const Spacer(),
              TextButton(
                onPressed: busy ? null : onRecheck,
                child: const Text('Recheck'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
