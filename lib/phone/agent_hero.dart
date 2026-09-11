import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart';

/// The row expanding into the header of the page it opens.
///
/// ⚠️ **The Hero carries the HEADER, not the whole page.** Two earlier versions got this wrong in
/// opposite directions and both read as broken:
///
///  - Wrapping only the engine mark made one glyph fly across an otherwise ordinary push — a
///    detail escaping the transition rather than a transition.
///  - Wrapping the entire page made the flight cover the screen while the route was also fading,
///    so two full-screen layers crossed and the screen visibly flashed at both ends.
///
/// A row is header-shaped: a mark, a title, a status line, 70pt tall. The terminal page's header is
/// the same shape. So the row becomes the header — one object, one motion — and the terminal body
/// below it arrives on its own, sliding up under a header that has already landed. That is also the
/// order the data is ready in: the header can be drawn from the agent immediately, the terminal
/// cannot be drawn until the pane attaches.
///
/// ⚠️ **The tag must include where the flight STARTED, not just the agent.**
///
/// The phone shell is an [IndexedStack] of three tabs, and every tab stays MOUNTED — that is what
/// lets a tab remember its stack. Both the Agents tab and the Machines tab draw rows for the same
/// agents, so keying on the agent alone puts two Heroes with one tag in the same subtree, and
/// Flutter throws `There are multiple heroes that share the same tag within a subtree` the moment
/// either is pushed from.
String agentHeroTag({
  required String machineId,
  required String agentId,
  required AgentHeroSource source,
}) => 'agent:$machineId/$agentId@${source.name}';

/// Which list a terminal page was opened from — the half of [agentHeroTag] that keeps two mounted
/// tabs from claiming one tag.
enum AgentHeroSource {
  /// The Agents tab's cross-machine list.
  agents,

  /// One machine's own agent list, under the Machines tab.
  machine,
}

/// How long the body takes to arrive after the header has landed.
const Duration kAgentBodyDelay = Duration(milliseconds: 90);

/// How long the flight itself runs. Longer than Material's 300ms default: the box travels most of
/// the screen's height, and at 300ms that distance reads as a jump rather than a movement.
const Duration kAgentHeroDuration = Duration(milliseconds: 340);

/// Wraps a list row so it expands into the page's header.
///
/// [tag] is null where there is nothing to fly to — an agent with no terminal does not open, so a
/// Hero on it would be a tag with one end. That case draws the plain child.
class AgentHeroCard extends StatelessWidget {
  const AgentHeroCard({super.key, required this.tag, required this.child});

  final String? tag;
  final Widget child;

  @override
  Widget build(BuildContext context) => _wrap(tag, child);
}

/// The header end of the flight.
class AgentHeroHeader extends StatelessWidget {
  const AgentHeroHeader({super.key, required this.tag, required this.child});

  final String? tag;
  final Widget child;

  @override
  Widget build(BuildContext context) => _wrap(tag, child);
}

Widget _wrap(String? tag, Widget child) {
  if (tag == null) return child;
  return Hero(
    tag: tag,
    // A straight rect tween, not Material's default arc. The row and the header are both at the top
    // of the screen and differ mostly in width, so an arced path bows the box sideways on the way —
    // motion across an axis the two ends do not actually differ on.
    createRectTween: (begin, end) => RectTween(begin: begin, end: end),
    flightShuttleBuilder: (_, animation, direction, fromContext, toContext) =>
        _Shuttle(
          animation: animation,
          forward: direction == HeroFlightDirection.push,
          from: (fromContext.widget as Hero).child,
          to: (toContext.widget as Hero).child,
        ),
    child: child,
  );
}

/// What is drawn while the row is becoming the header.
///
/// The box itself is what moves — Flutter tweens its rect — and this only has to make the surface
/// inside it change from a card to a page header: the corner straightens and the row's fill drains
/// away to nothing, because the header sits directly on the page rather than on a card.
///
/// The two ends cross-fade over the middle of the flight rather than at its edges. At the start the
/// box is still row-shaped and the row's own layout is the only one that fits it; at the end it is
/// header-shaped and the header's is. Swapping in the middle is the one point where neither is
/// visibly wrong.
class _Shuttle extends StatelessWidget {
  const _Shuttle({
    required this.animation,
    required this.forward,
    required this.from,
    required this.to,
  });

  final Animation<double> animation;
  final bool forward;
  final Widget from;
  final Widget to;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    // On a pop the flight runs backwards, so read the animation the other way for every tween below
    // to follow the direction of travel.
    final t = forward
        ? animation
        : ReverseAnimation(animation) as Animation<double>;
    final eased = CurvedAnimation(parent: t, curve: Curves.easeInOutCubic);
    return AnimatedBuilder(
      animation: eased,
      builder: (context, _) {
        final v = eased.value;
        // The card's surface fades out rather than lerping to the page colour: the header has no
        // fill of its own, and lerping to `windowBg` would paint an opaque rectangle over whatever
        // the page is drawing behind the header — the flash the full-page version had.
        final fill = AppGlass.rowFill.withValues(
          alpha: AppGlass.rowFill.a * (1 - v),
        );
        return DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(AppCard.radius * (1 - v)),
            border: Border.all(
              color: AppGlass.hair.withValues(alpha: AppGlass.hair.a * (1 - v)),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppCard.radius * (1 - v)),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (v < 0.6)
                  Opacity(
                    opacity: (1 - v / 0.6).clamp(0.0, 1.0),
                    child: _Loose(child: from),
                  ),
                if (v > 0.4)
                  Opacity(
                    opacity: ((v - 0.4) / 0.6).clamp(0.0, 1.0),
                    child: _Loose(child: to),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Lays a flight end out at its own natural height inside the moving box.
///
/// Both ends are built for a height they do not have mid-flight, and letting either lay out against
/// the in-between box makes it reflow on every frame. An unbounded height plus the clip above shows
/// whatever fits and hides the rest.
class _Loose extends StatelessWidget {
  const _Loose({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => OverflowBox(
    alignment: Alignment.topCenter,
    minHeight: 0,
    maxHeight: double.infinity,
    child: child,
  );
}

/// The terminal body, arriving after the header has landed.
///
/// Held back until the flight is nearly over and then slid up a short distance. Two reasons it is
/// not simply part of the page from the first frame: a full-screen terminal drawn behind a header
/// that is still mid-flight is the second layer that made the old version flash, and the body is
/// genuinely not ready that early — the pane attaches after the push.
class AgentBodyReveal extends StatefulWidget {
  const AgentBodyReveal({super.key, required this.child});

  final Widget child;

  @override
  State<AgentBodyReveal> createState() => _AgentBodyRevealState();
}

class _AgentBodyRevealState extends State<AgentBodyReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  /// Guards the one-time start: `didChangeDependencies` runs again on any inherited-widget change
  /// (a theme flip, a metrics change), and restarting the reveal there would replay it mid-session.
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // `ModalRoute.of` needs a context that is already in the tree, so this cannot be `initState`.
    //
    // A route with no animation, or one already finished — a rebuild, a page restored under an
    // existing one — resolves immediately and the body is simply there. Only a live push waits.
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.isCompleted) {
      _controller.value = 1;
      return;
    }
    Future<void>.delayed(kAgentBodyDelay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        // A short rise — 4% of the body's height. Enough to read as arriving from under the header,
        // small enough that nothing is off-screen long enough to notice.
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(curve),
        child: widget.child,
      ),
    );
  }
}
