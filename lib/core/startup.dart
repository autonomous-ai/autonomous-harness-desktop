import '../grid/grid_selection_store.dart';
import '../grid/grid_session.dart';
import '../grid/model_recents_store.dart';
import '../grid/provider_enablement_store.dart';
import '../shared/theme/appearance_prefs_store.dart';
import '../shared/theme/theme_mode_store.dart';
import '../stats/harness_stats.dart';
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
  GridSessionStore? gridSession,
  ProviderEnablementStore? providerEnablement,
  ModelRecentsStore? modelRecents,
  AppearancePrefsStore? appearance,
  HarnessStats? stats,
}) async {
  await (themeMode ?? themeModeStore).load();
  await (terminalFont ?? terminalFontStore).load();
  // The sidebar names the chosen grid in its first frame; loading this later
  // would show "No grid" and then snap to the real choice.
  await (gridSelection ?? gridSelectionStore).load();
  // Before the first frame for the same reason as the selection above: the Grid
  // pane and the status rail both ask "are we signed in" as they build, and a
  // session that arrived a frame later would show the sign-in prompt and then
  // snap away from under whoever was reaching for it.
  await (gridSession ?? gridSessionStore).load();
  // Before the first frame too: the sidebar's provider pill lists only enabled
  // providers, so a set that landed a frame later would show the full list and
  // then drop rows out from under a menu somebody had already opened.
  await (providerEnablement ?? providerEnablementStore).load();
  // Before the first frame for the same reason as the two above, and it is the
  // model picker's top section: recents that landed a frame late would push
  // every provider's rows down under a pointer already on its way to one.
  await (modelRecents ?? modelRecentsStore).load();
  // Last but not optional. Every control box in the app is sized from
  // `AppControl.heightScaled`/`paddingScaled`, so a UI size that arrived after
  // the first frame would relayout the whole window one frame in — a worse
  // flicker than a late theme, because the geometry moves and not just the ink.
  await (appearance ?? appearancePrefsStore).load();
  // Not for the first frame — nothing paints these counters until Settings ▸
  // Usage is opened. It is loaded here anyway because the counters START moving
  // as soon as an agent does, and a load that landed after the first
  // `onAgentSpawned` would overwrite it with the number from disk.
  await (stats ?? harnessStats).load();
}
