/// Who can reach a grid — the `network_type` a create sends, and the words the
/// picker shows for it.
///
/// Ported from the Grid app. The wire values are the control plane's own and
/// must not be prettied up; the labels are the app's, and the two are kept in
/// one place so a rename of either cannot leave them disagreeing.
enum GridAccessType {
  restricted(
    'permissioned-public',
    'Invite only',
    'Only people you invite can use this grid, or start an AI node to '
        'power it.',
  ),
  domain(
    'domain-restricted',
    'My domain',
    'Anyone with an email on your domain can use this grid, or start an AI '
        'node to power it, as well as the people you invite.',
  ),
  anyone(
    'permissionless',
    'Public',
    'Anyone can use this grid, or start an AI node to power it.',
  );

  const GridAccessType(this.wire, this.label, this.description);

  /// Value sent as `network_type`.
  final String wire;

  /// Short name for the picker. "Anyone" alone would leave out the condition —
  /// there IS one, you have to be signed in to Grid.
  final String label;

  /// The plain-language line under the picker: who gets to *use* the grid, and
  /// who gets to *supply* it. The three are deliberately parallel, so the one
  /// clause that differs is the one carrying the choice.
  final String description;

  /// What a grid created with no explicit choice gets. Invite-only: the one
  /// rule that can be widened later without having already let anyone in.
  static const GridAccessType fallback = GridAccessType.restricted;
}

/// The access rules to offer, given whether the domain rule is available.
///
/// Pure so it can be tested without a server. The domain rule is filtered out
/// rather than disabled: a greyed cell invites "why not?", and the honest
/// answer — your email provider is public, so this rule would let in everyone
/// who uses it — is longer than the control.
List<GridAccessType> accessTypesFor({required bool canRestrictToDomain}) {
  if (canRestrictToDomain) return GridAccessType.values;
  return GridAccessType.values
      .where((type) => type != GridAccessType.domain)
      .toList();
}

/// What to call [type] in a picker, naming [domain] when there is one.
///
/// "@clc.fitus.edu.vn emails" IS the rule. "My domain" is a pronoun the owner
/// has to resolve themselves — and this is the one control where the whole
/// question is *which* domain gets in, so leaving it unsaid leaves out the
/// answer. The "@" and the plural matter: the bare form names something rather
/// than describing a rule, and an account whose domain is autonomous.ai may
/// well also have a *grid* called autonomous.ai in the same list.
String accessLabelFor(GridAccessType type, {String? domain}) {
  if (type != GridAccessType.domain) return type.label;
  final named = (domain ?? '').trim();
  return named.isEmpty ? type.label : '@$named emails';
}

/// What [type] permits, naming [domain] when there is one — the sentence under
/// the picker, kept in step with [accessLabelFor] so the two cannot disagree.
///
/// The domain ADMITS rather than excludes: people invited from other domains
/// keep working beside it, which is why the last clause is not optional.
String accessDescriptionFor(GridAccessType type, {String? domain}) {
  if (type != GridAccessType.domain) return type.description;
  final named = (domain ?? '').trim();
  if (named.isEmpty) return type.description;
  return 'Anyone with an @$named email can use this grid, or start an AI '
      'node to power it, as well as the people you invite.';
}
