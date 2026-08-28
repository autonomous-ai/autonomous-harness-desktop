import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// Opens [LinkMachineScreen] as a modal popup for [machineId], closing itself automatically once
/// linking succeeds or the prompt is dismissed (including a barrier tap/Escape, which counts as an
/// implicit dismiss so the caller's reactive gate doesn't just reopen it next frame).
///
/// This is a deliberate exception to the pane grid's normal "never block other tiles" rule (see
/// `AppNotifier.showMachinePane`'s doc comment) — a machine that still needs linking has nothing
/// else useful to show in its own tile, and a transient blocking prompt reads better here than a
/// permanent docked panel that looks like a second tab.
Future<void> showLinkMachineScreenDialog(
  BuildContext context,
  AppNotifier notifier,
  String machineId,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: ListenableBuilder(
        listenable: notifier,
        builder: (context, _) {
          final state = notifier.stateOf(machineId);
          final stillNeeded =
              state != null &&
              state.needsLink &&
              !notifier.isLinkPromptDismissed(machineId);
          if (!stillNeeded) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (Navigator.of(context).canPop()) Navigator.of(context).pop();
            });
            return const SizedBox.shrink();
          }
          return LinkMachineScreen(notifier: notifier, machineState: state);
        },
      ),
    ),
  );
  // Any close that isn't "linked successfully" (barrier tap, Escape, the in-card Close button)
  // must count as a dismiss, or the caller's reactive gate would just reopen this next rebuild.
  final state = notifier.stateOf(machineId);
  if (state != null && state.needsLink) {
    notifier.dismissLinkPrompt(machineId);
  }
}

/// Shown for a remote machine the local CLI's relay has no linked trust for yet. The CLI now owns
/// E2EE entirely (see the harness CLI's `harness link create`/`harness link import`, and
/// src/lib/remoteRelay.ts) — this screen holds no crypto state, it just walks the user through
/// generating a code in Harness on the OTHER machine and pasting it here.
class LinkMachineScreen extends StatefulWidget {
  final AppNotifier notifier;
  final MachineState machineState;
  const LinkMachineScreen({
    super.key,
    required this.notifier,
    required this.machineState,
  });

  @override
  State<LinkMachineScreen> createState() => _LinkMachineScreenState();
}

class _LinkMachineScreenState extends State<LinkMachineScreen> {
  final _tokenController = TextEditingController();
  bool _submitting = false;
  bool _showTroubleshootingDetails = false;
  String? _error;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    final error = await widget.notifier.importLinkToken(
      widget.machineState.machine.machineId,
      _tokenController.text,
    );
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = error;
    });
    if (error == null) _tokenController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final machineId = widget.machineState.machine.machineId;
    final machineName = widget.machineState.machine.displayName;

    return Container(
      width: 460,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
        color: AppColors.surface,
      ),
      child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.link, size: 32, color: AppColors.accent),
              const SizedBox(height: 6),
              Text(
                'Link this machine',
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
                '$machineName is online, but it is not linked to this computer yet.',
                style: TextStyle(
                  fontFamily: AppFonts.sans,
                  fontFamilyFallback: AppFonts.sansFallback,
                  fontSize: 11.2,
                  color: AppColors.mutedStrong,
                ),
              ),
              const SizedBox(height: 10),
              _StepTitle(number: '1', text: 'On $machineName, open Harness.'),
              const SizedBox(height: 8),
              const _StepTitle(
                number: '2',
                text: 'Go to the account menu and generate a code',
              ),
              const SizedBox(height: 4),
              Text(
                'Copy the code it shows you.',
                style: TextStyle(
                  fontFamily: AppFonts.sans,
                  fontFamilyFallback: AppFonts.sansFallback,
                  fontSize: 11.2,
                  color: AppColors.mutedStrong,
                ),
              ),
              const SizedBox(height: 6),
              const _AccountMenuBreadcrumb(),
              const SizedBox(height: 10),
              const _StepTitle(number: '3', text: 'Paste the code here'),
              const SizedBox(height: 6),
              TextField(
                key: const Key('link-token-field'),
                controller: _tokenController,
                minLines: 1,
                maxLines: 3,
                style: TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 12.5,
                  color: AppColors.textSoft,
                ),
                decoration: InputDecoration(
                  hintText: 'Paste code from $machineName',
                  hintStyle: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 12.5,
                  ),
                  prefixIcon: const Icon(Icons.key_outlined, size: 17),
                ),
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(
                  _error!,
                  style: TextStyle(
                    fontFamily: AppFonts.sans,
                    fontFamilyFallback: AppFonts.sansFallback,
                    fontSize: 11.2,
                    color: AppColors.danger,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  key: const Key('link-import-button'),
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Link machine',
                          style: TextStyle(fontSize: 13.5),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your previous agent will reconnect automatically after linking.',
                style: TextStyle(
                  fontFamily: AppFonts.sans,
                  fontSize: 11.2,
                  color: AppColors.mutedStrong,
                ),
              ),
              const SizedBox(height: 4),
              TextButton.icon(
                key: const Key('link-troubleshooting-details'),
                onPressed: () => setState(
                  () => _showTroubleshootingDetails =
                      !_showTroubleshootingDetails,
                ),
                icon: Icon(
                  _showTroubleshootingDetails
                      ? Icons.expand_less
                      : Icons.expand_more,
                  size: 16,
                ),
                label: const Text('Troubleshooting details'),
              ),
              if (_showTroubleshootingDetails)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: SelectableText(
                    'Machine ID: $machineId',
                    style: TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 11.2,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              // An explicit way out, in addition to the barrier tap/Escape that
              // showLinkMachineScreenDialog already treats as an implicit dismiss. Closing does
              // not pretend the machine is linked: it still cannot be read and the rail still
              // says so. It only stops the popup from insisting, and choosing that machine again
              // brings it straight back. Bottom-right text button, matching every other dialog in
              // the app (see link_machine_dialog.dart's 'Close').
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => widget.notifier.dismissLinkPrompt(machineId),
                  child: const Text('Close', style: TextStyle(fontSize: 13.5)),
                ),
              ),
            ],
          ),
    );
  }
}

/// A static (nothing to copy or tap) breadcrumb showing exactly where in the Harness account menu
/// to find the "generate a code" action, so the user recognizes it on sight rather than hunting.
class _AccountMenuBreadcrumb extends StatelessWidget {
  const _AccountMenuBreadcrumb();

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      fontFamily: AppFonts.sans,
      fontFamilyFallback: AppFonts.sansFallback,
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: AppColors.text,
    );
    final sepStyle = TextStyle(
      fontFamily: AppFonts.sans,
      fontFamilyFallback: AppFonts.sansFallback,
      fontSize: 11.5,
      color: AppColors.mutedStrong,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.hover,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      // Text.rich word-wraps this as one flowing paragraph — far more compact than a Wrap of
      // atomic chunks, since "Remote into another machine…" alone is wider than the card.
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: 'Account', style: labelStyle),
            TextSpan(text: '  ›  ', style: sepStyle),
            TextSpan(text: 'Remote into another machine…', style: labelStyle),
            TextSpan(text: '  ›  ', style: sepStyle),
            TextSpan(
              text: 'Generate',
              style: labelStyle.copyWith(color: AppColors.accent),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepTitle extends StatelessWidget {
  final String number;
  final String text;

  const _StepTitle({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
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
            number,
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
