import 'package:flutter/foundation.dart';

/// Whether this build shows Grid at all: Settings ▸ Grid, Settings ▸ Share
/// Intelligence, the machine rail's grid picker, and — through the selection
/// store below — the pane header's model control and the bottom strip's
/// readout.
///
/// Grid is still being built, so a shipped build keeps it out of sight rather
/// than offering a feature that is not finished being one. Its own flag and not
/// [kDebugSurfaceEnabled]: Debug and Tracking are developer *furniture* and
/// Grid is a *feature in progress*, and folding the two together would mean a
/// build that shows one has to show the other.
///
/// The gate is deliberately wider than the two surfaces it hides. Everything
/// downstream of a picked grid — where a new agent's tokens go, what the header
/// says about a running one, what the status rail counts — reads
/// `gridSelectionStore`, and that store is persisted in `~/.harness`, shared
/// with the debug build that DOES let a grid be picked. So the store refuses to
/// load one here (see `GridSelectionStore.load`), which leaves a release build
/// behaving exactly as a machine that never chose a grid rather than acting on
/// one its user has no way to see or change.
///
/// `HARNESS_GRID_SURFACE=true` turns it on in a release build — for a demo, or
/// for testing the packaged app against a real grid.
const bool kGridSurfaceEnabled =
    kDebugMode || bool.fromEnvironment('HARNESS_GRID_SURFACE');
