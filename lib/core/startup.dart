import '../grid/grid_selection_store.dart';
import '../shared/theme/appearance_prefs_store.dart';
import '../shared/theme/theme_mode_store.dart';
import '../terminal/terminal_font_store.dart';

/// Every preference that has to be in place BEFORE the first frame.
///
/// Extracted from `main()` so it can be tested. A store that is never loaded still passes every one
/// of its own tests — it round-trips through disk perfectly — and silently forgets the user's
/// choice at the next launch. Nothing else in the suite would notice, because the only thing wrong
/// is a missing call in the entrypoint. This is that call, in a place a test can reach.
///
/// Both are awaited before `runApp` rather than loaded lazily: reading them after the first frame
/// would paint the defaults and then snap to the saved values, which reads as a flicker on every
/// launch.
///
/// The parameters exist for tests; the app passes nothing and gets the singletons the widgets read.
Future<void> loadPersistedSettings({
  ThemeModeStore? themeMode,
  TerminalFontStore? terminalFont,
  GridSelectionStore? gridSelection,
  AppearancePrefsStore? appearance,
}) async {
  await (themeMode ?? themeModeStore).load();
  await (terminalFont ?? terminalFontStore).load();
  // The sidebar names the chosen grid in its first frame; loading this later
  // would show "each engine's own login" and then snap to the real choice.
  await (gridSelection ?? gridSelectionStore).load();
  // Last but not optional. Every control box in the app is sized from
  // `AppControl.heightScaled`/`paddingScaled`, so a UI size that arrived after
  // the first frame would relayout the whole window one frame in — a worse
  // flicker than a late theme, because the geometry moves and not just the ink.
  await (appearance ?? appearancePrefsStore).load();
}
