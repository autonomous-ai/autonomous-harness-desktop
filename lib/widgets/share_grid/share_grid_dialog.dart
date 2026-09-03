import 'package:flutter/material.dart';

import '../../grid/grid_access.dart';
import '../../grid/grid_members_controller.dart';
import '../../grid/grid_network.dart';
import '../../grid/grid_networks_controller.dart';
import '../../grid/invite_email.dart';
import '../../grid/managed_network_member.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/labeled_field.dart';
import 'grid_role_menu.dart';
import 'share_grid_people.dart';

/// Everything about who can reach a grid, in one sheet — invite someone, see
/// who is already on it, and read how the grid is reachable in general.
///
/// Ported from Grid (`features/network/presentation/share_grid_dialog.dart`).
/// **Modelled on Google Docs' share sheet**, which is the shape non-technical
/// users already know: a full-width address field, the people below it, the
/// blanket rule at the bottom, and one primary button that closes the sheet.
/// Three of its habits are load-bearing:
///
/// - the address field is the only boxed control, so it is where the eye lands;
/// - a menu lists **labels and a tick**, and the sentence explaining a choice
///   lives in the row that opened it, at sheet width — a panel is only as wide
///   as its button, and Grid learned that the hard way with a menu that printed
///   "…can use this grid — includi…";
/// - the role for a person is a noun ("Use models", "Share a computer"), not a
///   clause.
///
/// **One thing Grid has and this does not: changing the access rule.** Here
/// "Who can join" states the rule and stops. See [gridAccessRule] for why —
/// short version, it restarts the grid under everyone on it, and every build of
/// this app currently shares one developer's Grid token.
Future<void> showShareGridDialog(
  BuildContext context, {
  required String networkId,
  required String gridName,
  GridNetworksController? networks,
  GridMembersController? members,
  VoidCallback? onChanged,
}) => showDialog<void>(
  context: context,
  builder: (_) => ShareGridDialog(
    networkId: networkId,
    gridName: gridName,
    networks: networks ?? gridNetworksController,
    members: members,
    onChanged: onChanged,
  ),
);

class ShareGridDialog extends StatefulWidget {
  const ShareGridDialog({
    super.key,
    required this.networkId,
    required this.gridName,
    required this.networks,
    this.members,
    this.onChanged,
  });

  final String networkId;

  /// What to call the grid in the title, before — and whether or not — the
  /// control plane answers with the rest of its detail.
  final String gridName;

  /// Where the account and this grid's own record come from: who the viewer is,
  /// what roles they hold, and whether they own it. Shared with Settings, so
  /// opening this after visiting Settings ▸ Grid costs no second request.
  final GridNetworksController networks;

  /// Injected by tests. The dialog otherwise makes — and disposes — its own.
  final GridMembersController? members;

  /// Told after every write that lands, so the status rail's member figure
  /// follows the list rather than waiting out its next poll.
  final VoidCallback? onChanged;

  @override
  State<ShareGridDialog> createState() => _ShareGridDialogState();
}

/// The sheet's width, and the inset every block inside it pays.
const double _sheetWidth = 512;
const double _sheetInset = 24;

class _ShareGridDialogState extends State<ShareGridDialog> {
  late final GridMembersController _members =
      widget.members ?? GridMembersController(networkId: widget.networkId);

  final _email = TextEditingController();
  final _emailFocus = FocusNode();
  bool _inviting = false;

  /// What the control plane said no to — a 403, a seat cap, a network error.
  /// Cleared the moment the address is edited, since it was about the old one.
  String? _serverError;

  /// What [inviteEmailError] says about the text in the field, once the user
  /// has finished a first attempt at it. Null until [_showErrors].
  String? _localError;

  /// Whether validation is allowed to speak yet.
  ///
  /// False while the address is being typed for the first time: every half-typed
  /// address is invalid, so live checking from keystroke one would sit there
  /// scolding someone who is doing nothing wrong. It flips on the first blur or
  /// the first Invite — after that the verdict updates on every keystroke, so it
  /// disappears the instant the address becomes usable.
  bool _showErrors = false;

  /// The one message the field shows. A server refusal outranks a syntax
  /// complaint: it is the newer fact, and it is about an address the client
  /// already accepted.
  String? get _error => _serverError ?? _localError;

  /// What the invited person will be able to do. Defaults to the widest grant —
  /// see [ManagedMemberRole.fallback]. Guessing narrower would silently withhold
  /// something the inviter meant to give.
  ManagedMemberRole _role = ManagedMemberRole.fallback;

  @override
  void initState() {
    super.initState();
    _members.ensureLoaded();
    widget.networks.ensureLoaded();
  }

  @override
  void dispose() {
    _email.dispose();
    _emailFocus.dispose();
    if (widget.members == null) _members.dispose();
    super.dispose();
  }

  /// This grid's own record, or null until the account answers — and forever on
  /// a grid the account is somehow not listed on.
  GridNetwork? get _network {
    final state = widget.networks.state;
    if (state is! GridNetworksReady) return null;
    for (final network in state.me.networks) {
      if (network.networkId == widget.networkId) return network;
    }
    return null;
  }

  String? get _viewerEmail {
    final state = widget.networks.state;
    return state is GridNetworksReady ? state.me.user.email : null;
  }

  /// The roles this viewer may hand out — never more than they hold themselves.
  ///
  /// The control plane enforces this too (403 `role_above_caller`); filtering
  /// here means the choice is never offered rather than refused after the fact.
  /// An account whose membership has not arrived yet falls to the narrowest,
  /// which is the safe direction.
  List<ManagedMemberRole> get _grantable =>
      invitableRolesFor(_network?.member?.roles ?? const []);

  /// [_role], clamped to what this viewer may actually grant.
  ///
  /// A getter rather than a correction written into [_role] during `build`:
  /// mutating state there is a side effect in a method that may run twice, and
  /// the clamp has to hold for the send too — one place, read by both.
  ManagedMemberRole get _effectiveRole {
    final grantable = _grantable;
    return grantable.contains(_role) ? _role : grantable.first;
  }

  /// Removing is the owner's alone, and deliberately: adding someone is
  /// reversible by whoever did it, while removing cuts off a colleague who may
  /// be mid-task on the grid.
  ///
  /// False until the account lands, so nobody is offered a control they may not
  /// have; it arrives a moment later and the column appears.
  bool _canRemove(GridNetwork? network) =>
      network != null && gridIsOwnedBy(network, _viewerEmail);

  /// Re-runs the address check, once [_showErrors] has let it speak.
  void _revalidate() {
    if (!_showErrors) return;
    final next = inviteEmailError(_email.text.trim());
    if (next != _localError) setState(() => _localError = next);
  }

  /// Leaving the field is a finished attempt — but only if there is something
  /// in it. Blurring an empty box is someone clicking elsewhere, not someone
  /// failing to type an address.
  void _onFocusChange(bool hasFocus) {
    if (hasFocus || _email.text.trim().isEmpty) return;
    setState(() {
      _showErrors = true;
      _localError = inviteEmailError(_email.text.trim());
    });
  }

  Future<void> _invite() async {
    final email = _email.text.trim();
    // Checked here, not only on the server: a 422 comes back as one flat
    // "Invalid email", while `inviteEmailError` names the half that is broken.
    // The request is never sent when the client already knows the answer.
    final invalid = inviteEmailError(email);
    if (invalid != null) {
      setState(() {
        _showErrors = true;
        _localError = invalid;
        _serverError = null;
      });
      _emailFocus.requestFocus();
      return;
    }

    setState(() {
      _inviting = true;
      _serverError = null;
      _localError = null;
    });

    final error = await _members.invite(email: email, role: _effectiveRole);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _inviting = false;
        _serverError = error;
      });
      return;
    }

    // The dialog stays open on purpose: the person lands in the list right
    // below, which is the whole reason the invite and the list share a sheet.
    widget.onChanged?.call();
    setState(() {
      _inviting = false;
      _email.clear();
      // The next address starts clean: the field is empty again, and an empty
      // field has not been got wrong yet.
      _showErrors = false;
      _localError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return ListenableBuilder(
      listenable: Listenable.merge([_members, widget.networks]),
      builder: (context, _) => AlertDialog(
        // Deliberately **not** `scrollable: true`. That flag wraps the content
        // in an `IntrinsicWidth`, which asks every child for its natural height;
        // the people list is a `ListView` and cannot answer. Grid's own sheet
        // walked into it and froze the app on open, spewing
        // `!_debugDuringDeviceUpdate` from the mouse tracker every frame.
        //
        // The one part that can outgrow the window scrolls on its own instead;
        // see [SharePeopleList.maxHeight].
        titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        title: Text('Who can use “${widget.gridName}”'),
        // Zero, so the footer's hairline runs the full width of the sheet the
        // way Docs draws it. Every block below pays its own inset.
        contentPadding: EdgeInsets.zero,
        content: SizedBox(width: _sheetWidth, child: _content(context)),
        actionsPadding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
        actions: [
          // Docs closes with a single **Done** that saves nothing — everything
          // above took effect when it was pressed.
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context) {
    final network = _network;
    // Omitted entirely on a rule this app has no words for — see below.
    final rule = network == null ? null : gridAccessRule(network);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(_sheetInset, 16, _sheetInset, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _InviteField(
                controller: _email,
                focusNode: _emailFocus,
                enabled: !_inviting,
                hasError: _error != null,
                onSubmitted: _invite,
                onFocusChange: _onFocusChange,
                onChanged: () {
                  // The refusal was about the address that has just been
                  // edited, so it is out of date the moment a key lands.
                  if (_serverError != null) {
                    setState(() => _serverError = null);
                  }
                  _revalidate();
                },
              ),
              // The role and the send button appear only once there is
              // something to send — Docs' own behaviour, and what gives the
              // address field the whole width it needs.
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _email,
                builder: (context, value, _) => value.text.trim().isEmpty
                    ? const SizedBox.shrink()
                    : _InviteActions(
                        role: _effectiveRole,
                        roles: _grantable,
                        inviting: _inviting,
                        onRoleChanged: (role) => setState(() => _role = role),
                        onInvite: _invite,
                      ),
              ),
              if (_error case final message?) ...[
                const SizedBox(height: 12),
                _ErrorNote(message: message),
              ],
              const _Heading('Members'),
              SharePeopleList(
                controller: _members,
                canRemove: _canRemove(network),
                grantable: _grantable,
                viewerEmail: _viewerEmail,
                onFailure: (message) =>
                    setState(() => _serverError = message),
              ),
              // A sentence under this heading is read as a promise about who
              // is already in, so an unrecognised rule prints nothing rather
              // than a guess — the one mistake here nobody could catch.
              if (rule != null) ...[
                const _Heading('Who can join'),
                _AccessRow(rule: rule),
              ],
              const SizedBox(height: 20),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: AppPalette.divider),
      ],
    );
  }
}

/// The address field: full width, and the only boxed control in the sheet.
class _InviteField extends StatelessWidget {
  const _InviteField({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.hasError,
    required this.onSubmitted,
    required this.onChanged,
    required this.onFocusChange,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool hasError;
  final VoidCallback onSubmitted;
  final VoidCallback onChanged;

  /// Leaving the field counts as a finished attempt — see `_onFocusChange`.
  final ValueChanged<bool> onFocusChange;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FieldLabel('Invite people'),
        Focus(
          onFocusChange: onFocusChange,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSubmitted(),
            onChanged: (_) => onChanged(),
            style: const TextStyle(fontSize: 14, height: 1.4),
            decoration: _decoration(context),
          ),
        ),
      ],
    );
  }

  /// The app's field on a raised surface, plus the one rim it grows when the
  /// address in it is wrong.
  ///
  /// `AppCard.inset` because this sits on a dialog, not on the page — see
  /// [labeledFieldDecoration]. The error ring is built here rather than baked
  /// into that helper: it is the only field in the app that has an error state,
  /// and the colour has to come from the theme, which a context-free helper
  /// cannot reach.
  InputDecoration _decoration(BuildContext context) {
    final base = labeledFieldDecoration(
      'Email address',
      fill: AppCard.inset,
    );
    if (!hasError) return base;
    final rim = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppControl.radius),
      borderSide: BorderSide(
        color: Theme.of(context).colorScheme.error,
        width: 1.5,
      ),
    );
    // Focused too: a field the user has to go back and fix must stay findable
    // once they have clicked into it.
    return base.copyWith(
      border: rim,
      enabledBorder: rim,
      focusedBorder: rim,
    );
  }
}

/// The role for this invite and the button that sends it — shown only once an
/// address has been typed.
class _InviteActions extends StatelessWidget {
  const _InviteActions({
    required this.role,
    required this.roles,
    required this.inviting,
    required this.onRoleChanged,
    required this.onInvite,
  });

  final ManagedMemberRole role;
  final List<ManagedMemberRole> roles;
  final bool inviting;
  final ValueChanged<ManagedMemberRole> onRoleChanged;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GridRoleMenu(
                role: role,
                roles: roles,
                strong: true,
                enabled: !inviting,
                tooltip: 'What they can do',
                onRoleChanged: onRoleChanged,
              ),
              const Spacer(),
              FilledButton(
                onPressed: inviting ? null : onInvite,
                child: inviting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Invite'),
              ),
            ],
          ),
          // Under the role rather than beside it: a sentence squeezed into what
          // is left of the row wraps to three ragged lines caught between two
          // controls, and it explains the control on its left, so it reads
          // better hanging under it.
          Padding(
            padding: const EdgeInsets.only(left: 10, top: 6, right: 4),
            child: Text(
              role.description,
              style: TextStyle(
                color: AppPalette.textSecondary,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The blanket rule, stated. Drive puts one sentence under the rule's own name,
/// in the row rather than in a menu, and that is what keeps it from arriving
/// clipped: a row is as wide as the sheet.
class _AccessRow extends StatelessWidget {
  const _AccessRow({required this.rule});

  final GridAccessRule rule;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppCard.inset,
        borderRadius: BorderRadius.circular(AppCard.insetRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              rule.label,
              style: TextStyle(
                color: AppPalette.textPrimary,
                fontSize: 13,
                height: 1.2,
                fontWeight: AppFont.semibold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              rule.description,
              style: TextStyle(
                color: AppPalette.textSecondary,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the control plane refused, or what the address is missing.
class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final error = Theme.of(context).colorScheme.error;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: error.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(AppControl.radius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          message,
          style: TextStyle(color: error, fontSize: 12.5, height: 1.4),
        ),
      ),
    );
  }
}

/// A section title inside the sheet.
class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          color: AppPalette.textPrimary,
          fontSize: 13.5,
          fontWeight: AppFont.semibold,
        ),
      ),
    );
  }
}
