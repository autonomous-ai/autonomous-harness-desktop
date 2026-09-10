import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../theme/app_theme.dart';

class EngineIdentity {
  final String id;
  final String label;
  final Color color;

  /// The engine's colour AS A BAND — the stripe along the top of its pane.
  ///
  /// A separate value from [color] because the two are asked to do different jobs. [color] tints a
  /// small mark against a known background and may be white: Pi's is, and Grok's, and OpenCode's is
  /// #f1ecec. A stripe of white across the top of a pane is either invisible or a scar, depending on
  /// the theme. These are the values the product page publishes for exactly this stripe, which is where
  /// the design was settled — Claude's terracotta, Codex's periwinkle, Cursor's green, OpenCode's
  /// amber — and curated substitutes for the engines that page does not show.
  final Color accent;
  final String? asset;

  const EngineIdentity({
    required this.id,
    required this.label,
    required this.color,
    required this.accent,
    this.asset,
  });
}

const _engines = <String, EngineIdentity>{
  'claude': EngineIdentity(
    id: 'claude',
    label: 'Claude',
    color: Color(0xffcc7c5e),
    accent: Color(0xffd97757), // the product page value
  ),
  'codex': EngineIdentity(
    id: 'codex',
    label: 'Codex',
    color: Color(0xff64d2ff),
    accent: Color(0xffc4b5fd), // the product page value
    asset: 'assets/engine-icons/codex.png',
  ),
  'cursor': EngineIdentity(
    id: 'cursor',
    label: 'Cursor',
    color: Color(0xffc6ff72),
    accent: Color(0xff3ddc84), // the product page value
    asset: 'assets/engine-icons/cursor.png',
  ),
  'opencode': EngineIdentity(
    id: 'opencode',
    label: 'OpenCode',
    color: Color(0xfff1ecec),
    accent: Color(
      0xffffb340,
    ), // the product page value; its own #f1ecec is unusable as a band
    asset: 'assets/engine-icons/opencode.png',
  ),
  'pi': EngineIdentity(
    id: 'pi',
    label: 'Pi',
    color: Colors.white,
    accent: Color(
      0xffb39ddb,
    ), // substitute: its own white is unusable as a band
    asset: 'assets/engine-icons/pi.png',
  ),
  'hermes': EngineIdentity(
    id: 'hermes',
    label: 'Hermes',
    color: Color(0xff9b8cff),
    accent: Color(0xffffd700), // the product page value
    asset: 'assets/engine-icons/hermes.png',
  ),
  'commandcode': EngineIdentity(
    id: 'commandcode',
    label: 'Command Code',
    color: Color(0xfff5f5f5),
    accent: Color(
      0xffffb27a,
    ), // substitute: its own #f5f5f5 is unusable as a band
    asset: 'assets/engine-icons/commandcode.png',
  ),
  'devin': EngineIdentity(
    id: 'devin',
    label: 'Devin',
    color: Color(0xff8fb8ff),
    accent: Color(0xff8fb8ff), // its own colour, already band-safe
    asset: 'assets/engine-icons/devin.png',
  ),
  'muse': EngineIdentity(
    id: 'muse',
    label: 'Muse',
    color: Color(0xff0082fb),
    accent: Color(0xff0082fb), // its own colour, already band-safe
    asset: 'assets/engine-icons/muse.png',
  ),
  'amp': EngineIdentity(
    id: 'amp',
    label: 'Amp',
    color: Color(0xfff34e3f),
    accent: Color(0xfff34e3f), // its own colour, already band-safe
    asset: 'assets/engine-icons/amp.png',
  ),
  'kilo': EngineIdentity(
    id: 'kilo',
    label: 'Kilo',
    color: Color(0xfff8f676),
    accent: Color(0xfff8f676), // its own colour, already band-safe
    asset: 'assets/engine-icons/kilo.png',
  ),
  'grok': EngineIdentity(
    id: 'grok',
    label: 'Grok',
    color: Colors.white,
    accent: Color(
      0xffe6e6e6,
    ), // the product page value; its own white is unusable as a band
    asset: 'assets/engine-icons/grok.png',
  ),
  'copilot': EngineIdentity(
    id: 'copilot',
    label: 'Copilot',
    color: Color(0xff8957e5),
    accent: Color(0xff8957e5), // its own colour, already band-safe
    asset: 'assets/engine-icons/copilot.png',
  ),
  'agy': EngineIdentity(
    id: 'agy',
    label: 'Antigravity',
    color: Color(0xff3287fb),
    accent: Color(0xffe08239), // substitute: its own #3287fb sits on muse; taken from the warm apex of the same mark
    asset: 'assets/engine-icons/agy.png',
  ),
};

/// The engine's band colour, legible on the surface the current theme actually paints.
///
/// The published values are tuned against a dark pane, and several of them are very light — Grok's
/// #e6e6e6, Kilo's #f8f676, Hermes' #ffd700. On a white pane those are a stripe you cannot see, which
/// is worse than no stripe: the band is supposed to be how you tell two panes apart at a glance, and an
/// invisible one silently removes that for whole engines.
///
/// So in light mode anything too pale is taken down to a fixed lightness — the same hue, dark enough to
/// read on white. Dark mode is left exactly as published; nothing there needs help.
Color engineBand(String? engine) {
  final published = engineIdentity(engine).accent;
  if (grid.AppTheme.isDark) return published;
  final hsl = HSLColor.fromColor(published);
  if (hsl.lightness <= 0.62) return published;
  return hsl
      .withLightness(0.42)
      .withSaturation(math.max(hsl.saturation, 0.35))
      .toColor();
}

/// All known engines, in declaration order — for the New Agent engine picker.
List<EngineIdentity> get allEngines => _engines.values.toList(growable: false);

EngineIdentity engineIdentity(String? engine, {String? displayName}) {
  final id = engine?.trim().toLowerCase() ?? '';
  final known = _engines[id];
  if (known != null) return known;
  final raw = displayName?.trim().isNotEmpty == true
      ? displayName!.trim()
      : id.isEmpty
      ? 'Agent'
      : id;
  final label = raw[0].toUpperCase() + raw.substring(1);
  return EngineIdentity(
    id: id.isEmpty ? 'unknown' : id,
    label: label,
    color: AppColors.mutedStrong,
    // An engine this build has never heard of still gets a band, in the same grey its mark wears —
    // "we do not know this one" reads better as a quiet stripe than as a missing one.
    accent: AppColors.mutedStrong,
  );
}

class EngineMark extends StatelessWidget {
  final String? engine;
  final String? displayName;
  final bool enabled;
  final double size;

  const EngineMark({
    super.key,
    required this.engine,
    this.displayName,
    this.enabled = true,
    this.size = 16,
  });

  @override
  Widget build(BuildContext context) {
    final identity = engineIdentity(engine, displayName: displayName);
    final mark = identity.asset != null
        ? Image.asset(
            identity.asset!,
            key: ValueKey('engine-icon-${identity.id}'),
            width: size,
            height: size,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, _, _) => _InitialMark(
              key: ValueKey('engine-fallback-${identity.id}'),
              identity: identity,
              size: size,
            ),
          )
        : identity.id == 'claude'
        ? CustomPaint(
            key: const ValueKey('engine-icon-claude'),
            size: Size.square(size),
            painter: _ClaudeMarkPainter(identity.color),
          )
        : _InitialMark(
            key: ValueKey('engine-fallback-${identity.id}'),
            identity: identity,
            size: size,
          );
    return Opacity(opacity: enabled ? 1 : 0.45, child: mark);
  }
}

class _InitialMark extends StatelessWidget {
  final EngineIdentity identity;
  final double size;

  const _InitialMark({super.key, required this.identity, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Center(
        child: Text(
          identity.label.characters.first.toUpperCase(),
          // ⚠️ Sized from [size], a FIXED box, not from the type ramp — so it
          // must not take the app's UI scale either. At the top of the range the
          // glyph would grow while its 17px square did not, and the letter would
          // clip out of its own mark.
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            color: identity.color,
            // The app's mono stack, not a literal: `Menlo` names nothing on
            // Linux, so this initial was drawn in the proportional default
            // while every mark beside it was monospaced.
            fontFamily: AppFonts.mono,
            fontFamilyFallback: AppFonts.monoFallback,
            fontSize: size * 0.68,
            height: 1,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ClaudeMarkPainter extends CustomPainter {
  final Color color;
  const _ClaudeMarkPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.098
      ..strokeCap = StrokeCap.round;
    final c = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.39;
    for (var i = 0; i < 4; i++) {
      final angle = i * 0.78539816339;
      final dx = radius * math.cos(angle);
      final dy = radius * math.sin(angle);
      canvas.drawLine(c - Offset(dx, dy), c + Offset(dx, dy), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ClaudeMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}
