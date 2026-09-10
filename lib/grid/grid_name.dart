/// The longest grid name the control plane accepts (its create-time rule).
const int gridNameMaxLength = 64;

/// The characters the control plane accepts when a grid is created: starts with
/// a letter or digit, then letters, digits, spaces and `. _ -`. Checked here so
/// a name the API would reject never costs a round-trip — the 4xx body it
/// answers with is not a line to show a person. Length is checked separately,
/// for a message that says which rule was broken.
final RegExp _gridNamePattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9 _.\-]*$');

/// Why [name] can't be used as a grid name, in plain language — or null when
/// it's fine. [takenNames] are the account's other grid names: two grids with
/// the same name are indistinguishable in every list this app draws, so a
/// duplicate is rejected (case-insensitively) before the round-trip.
String? gridNameError(String name, {Iterable<String> takenNames = const []}) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'Enter a name for your provider.';
  if (trimmed.length > gridNameMaxLength) {
    return 'Keep the name to $gridNameMaxLength characters or fewer.';
  }
  if (!_gridNamePattern.hasMatch(trimmed)) {
    return 'Use letters, numbers, spaces, dots, dashes or underscores, '
        'starting with a letter or number.';
  }
  final lower = trimmed.toLowerCase();
  if (takenNames.any((n) => n.trim().toLowerCase() == lower)) {
    return 'You already have a provider called "$trimmed".';
  }
  return null;
}
