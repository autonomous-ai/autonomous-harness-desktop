import 'package:flutter/widgets.dart';

import '../core/viewer_mode.dart';

/// The shortest side under which a viewer draws its phone layout — Material's own compact
/// breakpoint, so an iPad keeps the rail beside its terminals.
const double kPhoneShortestSide = 600;

/// Whether this screen gets the phone layout: one agent at a time, reached machine → agents →
/// terminal, instead of the desktop's rail beside a grid of tiles.
///
/// A viewer build only. A desktop build always has a window wide enough for the rail, and
/// resizing one small must not turn it into a phone.
bool usePhoneLayout(BuildContext context) =>
    kViewerMode && MediaQuery.sizeOf(context).shortestSide < kPhoneShortestSide;
