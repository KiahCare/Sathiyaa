// Motion.
//
// One place for every animation in the app, so timing and easing stay
// consistent instead of each screen inventing its own. The rule followed
// throughout: motion explains where something came from or confirms that a
// tap landed. Nothing moves purely for decoration, and nothing blocks the
// user waiting for an animation to finish.
//
// Everything here honours the platform "reduce motion" setting — when that
// is on, the widgets still build, they just arrive instantly.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/sathiyaa_theme.dart';

/// Shared durations. Short enough that the app never feels slow.
class Dur {
  Dur._();
  static const micro = Duration(milliseconds: 120);
  static const quick = Duration(milliseconds: 220);
  static const normal = Duration(milliseconds: 340);
  static const slow = Duration(milliseconds: 520);
}

class Ease {
  Ease._();
  /// Decelerate — things entering the screen.
  static const enter = Curves.easeOutCubic;
  /// Accelerate — things leaving.
  static const exit = Curves.easeInCubic;
  /// A touch of overshoot for something appearing under the finger.
  static const pop = Curves.easeOutBack;
  static const standard = Curves.easeInOutCubic;
}

bool _reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

// ---------------------------------------------------------------------------
// ENTRANCE
// ---------------------------------------------------------------------------

/// Fades and lifts a widget into place once, on first build.
///
/// [index] staggers a list: card 0 starts immediately, card 1 60ms later, and
/// so on, which reads as the list settling rather than snapping in. The
/// stagger is capped so the tenth card is not left waiting.
class FadeInUp extends StatefulWidget {
  const FadeInUp({
    super.key,
    required this.child,
    this.index = 0,
    this.offset = 18,
    this.duration = Dur.normal,
    this.stagger = const Duration(milliseconds: 60),
    this.maxStagger = 6,
  });

  final Widget child;
  final int index;
  final double offset;
  final Duration duration;
  final Duration stagger;
  final int maxStagger;

  @override
  State<FadeInUp> createState() => _FadeInUpState();
}

class _FadeInUpState extends State<FadeInUp> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _fade = CurvedAnimation(parent: _c, curve: Ease.enter);
  late final Animation<Offset> _slide = Tween(
    begin: Offset(0, widget.offset / 100),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _c, curve: Ease.enter));

  @override
  void initState() {
    super.initState();
    final steps = widget.index.clamp(0, widget.maxStagger);
    Future<void>.delayed(widget.stagger * steps, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduced(context)) return widget.child;
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// Wraps a column's children in staggered [FadeInUp]s without repeating the
/// index by hand at every call site.
List<Widget> staggered(List<Widget> children, {int from = 0, double offset = 18}) {
  return List.generate(
    children.length,
    (i) => FadeInUp(index: from + i, offset: offset, child: children[i]),
  );
}

// ---------------------------------------------------------------------------
// TOUCH
// ---------------------------------------------------------------------------

/// Presses inward slightly while held. Used on cards and primary buttons so a
/// tap is acknowledged in the same frame it happens, before any navigation.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.972,
    this.haptic = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null && widget.onLongPress == null) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        if (widget.haptic) HapticFeedback.selectionClick();
        widget.onTap?.call();
      },
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down && !_reduced(context) ? widget.scale : 1,
        duration: Dur.micro,
        curve: Ease.standard,
        child: widget.child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PAGE TRANSITIONS
// ---------------------------------------------------------------------------

/// The app's push transition: the new page slides a short distance from the
/// right while fading, and the old one drifts slightly left. Shorter travel
/// than Material's default, which makes navigation feel quicker without
/// actually being faster.
class SathiyaaPageRoute<T> extends PageRouteBuilder<T> {
  SathiyaaPageRoute({required this.page, this.fromBottom = false})
      : super(
          transitionDuration: Dur.normal,
          reverseTransitionDuration: Dur.quick,
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: (context, anim, secondary, child) {
            if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
            final curved = CurvedAnimation(
              parent: anim,
              curve: Ease.enter,
              reverseCurve: Ease.exit,
            );
            final begin = fromBottom ? const Offset(0, 0.06) : const Offset(0.18, 0);
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween(begin: begin, end: Offset.zero).animate(curved),
                child: SlideTransition(
                  position: Tween(begin: Offset.zero, end: const Offset(-0.06, 0))
                      .animate(CurvedAnimation(parent: secondary, curve: Ease.standard)),
                  child: child,
                ),
              ),
            );
          },
        );

  final Widget page;
  final bool fromBottom;
}

/// Convenience so screens read `push(context, const FooScreen())`.
Future<T?> push<T>(BuildContext context, Widget page, {bool fromBottom = false}) {
  return Navigator.of(context).push<T>(SathiyaaPageRoute<T>(page: page, fromBottom: fromBottom));
}

// ---------------------------------------------------------------------------
// STATE CHANGES
// ---------------------------------------------------------------------------

/// Cross-fades between two states of the same area — a loading block becoming
/// a list, an empty state becoming content — instead of the list popping in.
class FadeSwitch extends StatelessWidget {
  const FadeSwitch({super.key, required this.child, this.duration = Dur.quick});

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: _reduced(context) ? Duration.zero : duration,
      switchInCurve: Ease.enter,
      switchOutCurve: Ease.exit,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(anim),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Counts up to a number when it changes. Used on earnings, hours and totals,
/// where watching the figure land makes it register.
class AnimatedFigure extends StatelessWidget {
  const AnimatedFigure({
    super.key,
    required this.value,
    this.style,
    this.prefix = '',
    this.suffix = '',
    this.decimals = 0,
    this.duration = Dur.slow,
  });

  final double value;
  final TextStyle? style;
  final String prefix;
  final String suffix;
  final int decimals;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: _reduced(context) ? Duration.zero : duration,
      curve: Ease.enter,
      builder: (_, v, __) => Text(
        '$prefix${v.toStringAsFixed(decimals)}$suffix',
        style: style ?? ST.figure,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// LOADING
// ---------------------------------------------------------------------------

/// A shimmer sweep for skeleton placeholders. Cheap: one animation controller
/// drives a gradient shader rather than animating layout.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});
  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1250))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduced(context)) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment(-1.4 + 2.8 * _c.value, -0.3),
          end: Alignment(-0.4 + 2.8 * _c.value, 0.3),
          colors: const [
            Color(0x00FFFFFF),
            Color(0x66FFFFFF),
            Color(0x00FFFFFF),
          ],
        ).createShader(bounds),
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// A skeleton block — the grey shape a card occupies before its data lands.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 7});
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: SC.hairlineCool.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// The card-shaped skeleton used while a list loads. Matches the real card's
/// geometry so nothing jumps when the data arrives.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.lines = 2, this.avatar = true});
  final int lines;
  final bool avatar;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: SC.surface,
          borderRadius: BorderRadius.circular(SC.rCard),
          border: Border.all(color: SC.hairline),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (avatar) ...[
              const SkeletonBox(width: 48, height: 48, radius: 14),
              const SizedBox(width: 13),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SkeletonBox(width: 150, height: 15),
                  for (var i = 0; i < lines; i++) ...[
                    const SizedBox(height: 9),
                    SkeletonBox(width: i.isEven ? double.infinity : 190, height: 11),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A column of skeleton cards.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 3, this.lines = 2, this.avatar = true});
  final int count;
  final int lines;
  final bool avatar;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        count,
        (i) => Padding(
          padding: EdgeInsets.only(bottom: i == count - 1 ? 0 : 12),
          child: SkeletonCard(lines: lines, avatar: avatar),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ATTENTION
// ---------------------------------------------------------------------------

/// A slow breathing pulse behind something live — the dot on an in-progress
/// visit, the ring on an active shift. Deliberately subtle and slow; a fast
/// pulse on a care app reads as alarm.
class LivePulse extends StatefulWidget {
  const LivePulse({super.key, this.color = SC.green, this.size = 10});
  final Color color;
  final double size;

  @override
  State<LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<LivePulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    );
    if (_reduced(context)) return dot;

    return SizedBox(
      width: widget.size * 2.6,
      height: widget.size * 2.6,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (_, __) => Container(
              width: widget.size * (1 + _c.value * 1.6),
              height: widget.size * (1 + _c.value * 1.6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: 0.28 * (1 - _c.value)),
              ),
            ),
          ),
          dot,
        ],
      ),
    );
  }
}

/// The tick that draws itself when something succeeds — payment confirmed,
/// booking accepted. Worth the moment it costs: it is the confirmation the
/// user is waiting for.
class SuccessCheck extends StatefulWidget {
  const SuccessCheck({super.key, this.size = 92, this.color = SC.green});
  final double size;
  final Color color;

  @override
  State<SuccessCheck> createState() => _SuccessCheckState();
}

class _SuccessCheckState extends State<SuccessCheck> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 620))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduced(context)) {
      return Icon(Icons.check_circle_rounded, size: widget.size, color: widget.color);
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final ring = Curves.easeOutCubic.transform((_c.value / 0.55).clamp(0.0, 1.0));
        final tick = Curves.easeOutBack.transform(
          ((_c.value - 0.35) / 0.65).clamp(0.0, 1.0),
        );
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: ring,
                  strokeWidth: 4,
                  color: widget.color,
                  backgroundColor: widget.color.withValues(alpha: 0.15),
                ),
              ),
              Transform.scale(
                scale: tick,
                child: Icon(Icons.check_rounded, size: widget.size * 0.5, color: widget.color),
              ),
            ],
          ),
        );
      },
    );
  }
}
