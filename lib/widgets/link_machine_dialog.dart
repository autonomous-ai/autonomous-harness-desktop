import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth/cli_link.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// Generates a code for THIS machine, for another machine to paste into its own `LinkMachineScreen`
/// ("Link this machine"). Pasting a code to link a specific machine lives only there — reached by
/// selecting that machine (see `machine_rail.dart`'s `selectMachineForSetup`), not duplicated here —
/// so this dialog has exactly one job: generate, and say where to take the result.
Future<void> showLinkMachineDialog(BuildContext context, AppNotifier notifier) {
  return showDialog<void>(
    context: context,
    builder: (context) => _LinkMachineDialog(notifier: notifier),
  );
}

class _LinkMachineDialog extends StatefulWidget {
  final AppNotifier notifier;

  const _LinkMachineDialog({required this.notifier});

  @override
  State<_LinkMachineDialog> createState() => _LinkMachineDialogState();
}

class _LinkMachineDialogState extends State<_LinkMachineDialog> {
  bool _generating = false;
  CliLinkCreateResult? _generated;
  String? _generateError;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    unawaited(widget.notifier.refreshLinkedMachines());
  }

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _generateError = null;
    });
    final result = await widget.notifier.createLinkToken();
    if (!mounted) return;
    setState(() {
      _generating = false;
      if (result.error != null || result.token == null) {
        _generateError =
            result.error ?? 'Could not read the code from the CLI.';
      } else {
        _generated = result;
      }
    });
  }

  Future<void> _copyToken() async {
    final token = _generated?.token;
    if (token == null) return;
    await Clipboard.setData(ClipboardData(text: token));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Link another machine'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Generate a code here so another machine can link to this "
                "one. To link a specific machine from here instead, select "
                "it in the sidebar — you'll get a \"Link this machine\" "
                "guide to paste a code there.",
                style: TextStyle(
                  fontFamily: AppFonts.sans,
                  fontFamilyFallback: AppFonts.sansFallback,
                  fontSize: 11.2,
                  color: AppColors.mutedStrong,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              _ActionCard(
                icon: Icons.login,
                title: 'Let another machine control this one',
                steps: const [
                  'Click Generate below to create a code for this machine.',
                  "On the OTHER machine, select this machine in the "
                      "sidebar (it'll show 'link required') and paste the "
                      "code there.",
                ],
                error: _generateError,
                child: _generated == null
                    ? Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          key: const Key('link-generate-button'),
                          onPressed: _generating ? null : _generate,
                          child: _generating
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Generate',
                                  style: TextStyle(fontSize: 13.5),
                                ),
                        ),
                      )
                    : _GeneratedToken(
                        token: _generated!.token!,
                        fingerprint: _generated!.fingerprint,
                        copied: _copied,
                        onCopy: _copyToken,
                      ),
              ),
              const SizedBox(height: 18),
              Text(
                'MACHINES YOU CAN REMOTE INTO',
                style: TextStyle(
                  fontFamily: AppFonts.sans,
                  fontFamilyFallback: AppFonts.sansFallback,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: AppColors.mutedStrong,
                ),
              ),
              const SizedBox(height: 8),
              ListenableBuilder(
                listenable: widget.notifier,
                builder: (context, _) {
                  if (widget.notifier.linkedMachinesLoading &&
                      widget.notifier.linkedMachines.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  }
                  final machines = widget.notifier.linkedMachines;
                  if (machines.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No machines linked yet.',
                        style: TextStyle(
                          fontFamily: AppFonts.sans,
                          fontFamilyFallback: AppFonts.sansFallback,
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final machine in machines)
                        _LinkedMachineRow(
                          machine: machine,
                          displayName: widget.notifier
                              .stateOf(machine.machineId)
                              ?.machine
                              .displayName,
                          onUnlink: () async {
                            await widget.notifier.unlinkMachine(
                              machine.machineId,
                            );
                          },
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close', style: TextStyle(fontSize: 13.5)),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> steps;
  final Widget child;
  final String? error;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.steps,
    required this.child,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.hover,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.accent),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontFamily: AppFonts.sans,
              fontFamilyFallback: AppFonts.sansFallback,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _ActionStep(number: i + 1, text: steps[i]),
          ],
          const SizedBox(height: 12),
          child,
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error!,
              style: TextStyle(
                fontFamily: AppFonts.sans,
                fontFamilyFallback: AppFonts.sansFallback,
                fontSize: 11,
                color: AppColors.danger,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Same "numbered badge + text" language as `link_machine_screen.dart`'s `_StepTitle` — sized
/// identically (20px badge, 12px w600 text) now that this dialog is single-column and no longer
/// needs to be squeezed into a ~250px card, so the two linking surfaces read as one design.
class _ActionStep extends StatelessWidget {
  final int number;
  final String text;

  const _ActionStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.accent,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: TextStyle(
              color: AppColors.background,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: AppFonts.sans,
              fontFamilyFallback: AppFonts.sansFallback,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
        ),
      ],
    );
  }
}

class _GeneratedToken extends StatelessWidget {
  final String token;
  final String? fingerprint;
  final bool copied;
  final VoidCallback onCopy;

  const _GeneratedToken({
    required this.token,
    required this.fingerprint,
    required this.copied,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onCopy,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.background,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    token,
                    maxLines: 2,
                    style: TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 11,
                      color: AppColors.text,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  copied ? Icons.check : Icons.copy,
                  size: 15,
                  color: copied ? AppColors.success : AppColors.mutedStrong,
                ),
              ],
            ),
          ),
        ),
        if (fingerprint != null) ...[
          const SizedBox(height: 8),
          Text(
            'This machine\'s fingerprint — verify it matches on the other side:',
            style: TextStyle(
              fontFamily: AppFonts.sans,
              fontFamilyFallback: AppFonts.sansFallback,
              fontSize: 10.5,
              color: AppColors.mutedStrong,
            ),
          ),
          const SizedBox(height: 3),
          SelectableText(
            fingerprint!,
            style: TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
        ],
        const SizedBox(height: 4),
        Text(
          'Valid 7 days.',
          style: TextStyle(
            fontFamily: AppFonts.sans,
            fontFamilyFallback: AppFonts.sansFallback,
            fontSize: 10.5,
            color: AppColors.muted,
          ),
        ),
      ],
    );
  }
}

class _LinkedMachineRow extends StatelessWidget {
  final LinkedMachine machine;
  final String? displayName;
  final Future<void> Function() onUnlink;

  const _LinkedMachineRow({
    required this.machine,
    required this.displayName,
    required this.onUnlink,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName ?? machine.machineId,
                  style: TextStyle(
                    fontFamily: AppFonts.sans,
                    fontFamilyFallback: AppFonts.sansFallback,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                Text(
                  '${machine.fingerprint} · linked ${machine.linkedAt}',
                  style: TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 10.5,
                    color: AppColors.mutedStrong,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            key: Key('unlink-${machine.machineId}'),
            onPressed: () => unawaited(onUnlink()),
            child: const Text('Unlink', style: TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}
