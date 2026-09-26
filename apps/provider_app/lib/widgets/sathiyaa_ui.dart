// The Sathiyaa component set.
//
// These are the pieces the reference build repeats on every screen. Having
// them in one place is what stops the twentieth screen from drifting: a card
// is a card, a status chip is a status chip, and nobody re-guesses a radius.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/sathiyaa_theme.dart';
import '../languages.dart';
import 'motion.dart';
import '../i18n/l10n.dart';

// ---------------------------------------------------------------------------
// LANGUAGES
// ---------------------------------------------------------------------------

/// Tick the languages somebody speaks.
///
/// Shared, and in the design system rather than on one screen, because it is
/// asked in three places -- a carer registering, an organisation adding
/// staff, and a profile being corrected -- and the three have to offer the
/// same words. They read the same [kLanguages] list the customer app's search
/// filter reads, so a family cannot filter for a language no carer was ever
/// offered.
///
/// This is the control that did not exist. The provider app sent
/// `languages: ['English']` as a constant for every carer who ever
/// registered, while the customer app filtered on the field and printed it on
/// every result card.
class LanguagePicker extends StatelessWidget {
  const LanguagePicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final language in kLanguages)
          PressableScale(
            scale: 0.94,
            onTap: () {
              final next = Set<String>.from(selected);
              if (!next.remove(language)) next.add(language);
              onChanged(next);
            },
            child: AnimatedContainer(
              duration: Dur.micro,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: selected.contains(language) ? SC.blueBright : SC.surface,
                borderRadius: BorderRadius.circular(SC.rPill),
                border: Border.all(
                    color: selected.contains(language) ? SC.blueBright : SC.hairlineCool),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected.contains(language)) ...[
                    const Icon(Icons.check_rounded, size: 15, color: Colors.white),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    // Through t(), so the list reads in the language the app
                    // is set to -- somebody using the app in Gujarati should
                    // see ગુજરાતી, not "Gujarati".
                    t(language),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: selected.contains(language) ? Colors.white : SC.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// BRAND MARK
// ---------------------------------------------------------------------------

/// The Sathiyaa shield.
///
/// One widget rather than an Image.asset at each site, because the mark
/// appears at five sizes across the two apps and hand-placed copies drift --
/// different padding, different disc, and one of them left on the old
/// placeholder icon after a redesign. That is exactly what had happened: the
/// splash carried a heart, the two home headers carried a health-and-safety
/// glyph, and none of them was the logo.
///
/// The asset is the shield alone, cropped away from the wordmark in the brand
/// PDF. Two reasons: a wordmark is unreadable inside a 46px circle, and the
/// PDF's wordmark reads KUCH KARTE HAI while the app and the website say
/// Sathiyaa. Every place this appears also sets "Sathiyaa" in type beside it.
class SathiyaaLogo extends StatelessWidget {
  const SathiyaaLogo({super.key, this.size = 46, this.onPaper = false});

  /// Diameter of the whole mark, disc included.
  final double size;

  /// True when it sits on paper rather than on the brand gradient. The shield
  /// is already white inside, so the disc behind it is only there to lift it
  /// off the dark spine; on paper it is dropped and the mark drawn full size.
  final bool onPaper;

  @override
  Widget build(BuildContext context) {
    final glyph = size * (onPaper ? 1.0 : 0.72);
    final image = Image.asset(
      'assets/logo.png',
      width: glyph,
      height: glyph,
      filterQuality: FilterQuality.medium,
      // A missing asset throws a grey box with red text across the header.
      // The mark is decorative next to a title that already says the name, so
      // failing quietly is the right trade.
      errorBuilder: (_, __, ___) => Icon(
        Icons.health_and_safety_rounded,
        size: glyph * 0.8,
        color: onPaper ? SC.navy : SC.blue,
      ),
    );
    if (onPaper) return SizedBox(width: size, height: size, child: image);
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: image,
    );
  }
}

// ---------------------------------------------------------------------------
// HEADER
// ---------------------------------------------------------------------------

/// The curve along the bottom of the brand header. Two shallow control points
/// rather than one, so it reads as a sweep rather than a bubble.
class _HeaderCurve extends CustomClipper<Path> {
  @override
  Path getClip(Size s) {
    final p = Path()..lineTo(0, s.height - 34);
    p.cubicTo(s.width * 0.28, s.height - 2, s.width * 0.62, s.height - 46, s.width, s.height - 26);
    p.lineTo(s.width, 0);
    p.close();
    return p;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> old) => false;
}

/// The gradient block at the top of a screen. [compact] is the plain title
/// bar; leave it false for the tall greeting variant on Home.
class BrandHeader extends StatelessWidget {
  const BrandHeader({
    super.key,
    required this.child,
    this.height,
    this.curved = true,
  });

  final Widget child;
  final double? height;
  final bool curved;

  @override
  Widget build(BuildContext context) {
    final block = Container(
      width: double.infinity,
      height: height,
      decoration: const BoxDecoration(gradient: SC.brandGradient),
      child: Stack(
        children: [
          // A single soft highlight so the flat gradient has some depth.
          Positioned(
            right: -60,
            top: -40,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          // The curve eats ~34px off the bottom edge. Reserving it here means
          // no caller has to remember, and a header's subtitle can never be
          // sliced in half by the clip.
          SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.only(bottom: curved ? 38 : 8),
              child: child,
            ),
          ),
        ],
      ),
    );
    return curved ? ClipPath(clipper: _HeaderCurve(), child: block) : block;
  }
}

/// Logo + title on the left, actions on the right. Used inside [BrandHeader].
class BrandBar extends StatelessWidget {
  const BrandBar({
    super.key,
    this.title,
    this.subtitle,
    this.onBack,
    this.actions = const [],
    this.onDark = true,
  });

  final String? title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final fg = onDark ? Colors.white : SC.ink;
    return Padding(
      padding: const EdgeInsets.fromLTRB(SC.gutter, 10, SC.gutter, 10),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              onPressed: onBack,
              icon: Icon(Icons.chevron_left_rounded, color: fg, size: 30),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          if (onBack != null) const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null)
                  Text(t(title!),
                      style: ST.h1.copyWith(color: fg, fontSize: 22),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(right: 7),
                          decoration: const BoxDecoration(color: SC.gold, shape: BoxShape.circle),
                        ),
                        Flexible(
                          child: Text(t(subtitle!),
                              style: ST.body.copyWith(
                                  color: onDark ? Colors.white70 : SC.inkSoft, fontSize: 13.5),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// The round icon button used for the bell in the header.
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.badge = false,
    this.onDark = true,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool badge;
  final bool onDark;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final btn = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: onDark ? Colors.white.withValues(alpha: 0.16) : SC.blueTint,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: onDark ? Colors.white.withValues(alpha: 0.22) : SC.hairlineCool),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, color: onDark ? Colors.white : SC.blueBright, size: 21),
            if (badge)
              Positioned(
                top: 9,
                right: 10,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: SC.gold,
                    shape: BoxShape.circle,
                    border: Border.all(color: onDark ? SC.blue : SC.paper, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    // A Tooltip here rendered as a dark box over the header on web — it stays
    // up after a pointer passes over, and on a phone it only ever appears on a
    // long press, which nobody does. Semantics gives a screen reader the same
    // label without painting anything.
    return tooltip == null ? btn : Semantics(label: tooltip, button: true, child: btn);
  }
}

// ---------------------------------------------------------------------------
// AVATARS
// ---------------------------------------------------------------------------

/// Initials on a colour derived from the name, so the same person is always
/// the same colour without storing one. Falls back to this when there is no
/// photo, which in practice is most of the time.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({
    super.key,
    required this.name,
    this.size = 56,
    this.radius,
    this.image,
    this.badge,
    this.badgeColor,
    this.footer,
  });

  final String name;
  final double size;
  final double? radius;
  final ImageProvider? image;
  final IconData? badge;
  final Color? badgeColor;

  /// The little "Available" / "Busy" tag that sits across the bottom edge.
  final String? footer;

  static const _palette = [
    Color(0xFF3C6E8F), Color(0xFF7A4B63), Color(0xFF4A6B45),
    Color(0xFF8A5A3C), Color(0xFF5B4B8A), Color(0xFF2F6E6B),
    Color(0xFF8A4B4B), Color(0xFF41608C),
  ];

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }

  Color get _bg {
    var h = 0;
    for (final c in name.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return _palette[h % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final r = radius ?? size * 0.28;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(r),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_bg, Color.lerp(_bg, Colors.black, 0.22)!],
              ),
              image: image == null ? null : DecorationImage(image: image!, fit: BoxFit.cover),
            ),
            alignment: Alignment.center,
            child: image != null
                ? null
                : Text(_initials,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: size * 0.34,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    )),
          ),
          if (badge != null)
            Positioned(
              top: -3,
              right: -3,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: badgeColor ?? SC.green,
                  shape: BoxShape.circle,
                  border: Border.all(color: SC.surface, width: 2),
                ),
                child: Icon(badge, size: size * 0.2, color: Colors.white),
              ),
            ),
          if (footer != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: -2,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: footer == 'Busy' ? SC.inkFaint : SC.green,
                    borderRadius: BorderRadius.circular(SC.rPill),
                    border: Border.all(color: SC.surface, width: 1.6),
                  ),
                  child: Text(footer!,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CARDS
// ---------------------------------------------------------------------------

class SCard extends StatelessWidget {
  const SCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.border,
    this.margin,
    this.shadow = true,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? border;
  final EdgeInsets? margin;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? SC.surface,
        borderRadius: BorderRadius.circular(SC.rCard),
        border: Border.all(color: border ?? SC.hairline),
        boxShadow: shadow ? SC.cardShadow : null,
      ),
      clipBehavior: Clip.antiAlias,
      // A transparent Material inside the decoration, so anything that paints
      // ink — a ListTile, a SwitchListTile, an InkWell — has a surface to
      // paint it on. Without this Flutter asserts that the splash will be
      // hidden behind the card's own background, and the ripple never shows.
      child: Material(
        type: MaterialType.transparency,
        child: Padding(padding: padding, child: child),
      ),
    );
    return onTap == null ? body : PressableScale(onTap: onTap, child: body);
  }
}

/// The dark gradient card — bill summary, the active-service block, the
/// service banner on the payment screen.
class DarkCard extends StatelessWidget {
  const DarkCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.gradient,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final Gradient? gradient;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      decoration: BoxDecoration(
        gradient: gradient ?? SC.brandGradientDeep,
        borderRadius: BorderRadius.circular(SC.rCard),
        boxShadow: SC.liftShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -50,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.055),
              ),
            ),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
    return onTap == null ? body : PressableScale(onTap: onTap, child: body);
  }
}

// ---------------------------------------------------------------------------
// LABELS, CHIPS, PILLS
// ---------------------------------------------------------------------------

/// A gold rule and a title — the section marker used down the profile form.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(color: SC.gold, borderRadius: BorderRadius.circular(2)),
          ),
          Expanded(child: Text(text, style: ST.h2)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// The uppercase label above a form field.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.required = false});
  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7, left: 2),
      child: Text.rich(TextSpan(children: [
        TextSpan(text: text.toUpperCase(), style: ST.label),
        if (required)
          const TextSpan(
            text: ' *',
            style: TextStyle(color: SC.red, fontWeight: FontWeight.w800, fontSize: 12.5),
          ),
      ])),
    );
  }
}

enum ChipTone { neutral, good, warn, bad, info, gold }

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.tone = ChipTone.neutral, this.icon, this.dense = false});

  final String label;
  final ChipTone tone;
  final IconData? icon;
  final bool dense;

  (Color, Color) get _colors => switch (tone) {
        ChipTone.good => (SC.greenTint, const Color(0xFF1F7A45)),
        ChipTone.warn => (SC.amberTint, const Color(0xFFA9670F)),
        ChipTone.bad => (const Color(0xFFFCE9EA), SC.redDeep),
        ChipTone.info => (SC.blueTint, SC.blueLink),
        ChipTone.gold => (SC.goldTint, const Color(0xFF8A6317)),
        ChipTone.neutral => (const Color(0xFFF2F4F6), SC.inkSoft),
      };

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _colors;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 9 : 11, vertical: dense ? 4 : 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(SC.rPill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: dense ? 12 : 14, color: fg), const SizedBox(width: 5)],
          Text(t(label),
              style: TextStyle(
                  color: fg, fontSize: dense ? 11.5 : 12.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// The small outlined tag on a provider card — Nurse, Companion, Homecare.
class SkillTag extends StatelessWidget {
  const SkillTag(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: SC.blueTint,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(t(label),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: SC.blue)),
    );
  }
}

/// The segmented control — Book Companion | My Requests.
class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.tabs,
    required this.index,
    required this.onChanged,
    this.badges = const {},
  });

  final List<String> tabs;
  final int index;
  final ValueChanged<int> onChanged;

  /// Tab index -> count shown as a red pip.
  final Map<int, int> badges;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: SC.blueTint,
        borderRadius: BorderRadius.circular(SC.rPill),
      ),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final on = i == index;
          final badge = badges[i];
          return Expanded(
            child: PressableScale(
              scale: 0.96,
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: Dur.quick,
                curve: Ease.standard,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: on ? SC.blueBright : Colors.transparent,
                  borderRadius: BorderRadius.circular(SC.rPill),
                  boxShadow: on ? SC.cardShadow : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(t(tabs[i]),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: on ? Colors.white : SC.navy,
                          )),
                    ),
                    if (badge != null && badge > 0) ...[
                      const SizedBox(width: 7),
                      Container(
                        width: 21,
                        height: 21,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(color: SC.red, shape: BoxShape.circle),
                        child: Text('$badge',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Scrollable filter chips — All / Unread (3) / Messages.
class FilterChipRow extends StatelessWidget {
  const FilterChipRow({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.counts = const {},
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final Map<int, int> counts;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: SC.gutter),
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final on = i == index;
          final n = counts[i];
          return GestureDetector(
            onTap: () => onChanged(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? SC.navy : SC.surface,
                borderRadius: BorderRadius.circular(SC.rPill),
                border: Border.all(color: on ? SC.navy : SC.hairline),
              ),
              child: Row(
                children: [
                  Text(t(labels[i]),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: on ? Colors.white : SC.navy,
                      )),
                  if (n != null && n > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(color: SC.gold, shape: BoxShape.circle),
                      child: Text('$n',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// BOTTOM NAVIGATION
// ---------------------------------------------------------------------------

class NavItem {
  const NavItem(this.icon, this.label, {this.dot = false});
  final IconData icon;
  final String label;
  final bool dot;
}

/// The floating pill bar. Sits above the content with a rounded surface, and
/// leaves room for the system gesture bar underneath.
class PillNavBar extends StatelessWidget {
  const PillNavBar({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
  });

  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.fromLTRB(14, 0, 14, 10 + MediaQuery.of(context).padding.bottom * 0.4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: SC.surface,
        borderRadius: BorderRadius.circular(SC.rPill),
        border: Border.all(color: SC.hairline),
        boxShadow: SC.liftShadow,
      ),
      child: Row(
        children: List.generate(items.length, (i) {
          final on = i == index;
          final it = items[i];
          // Three small movements, and deliberately no more: the pill fills,
          // the icon lifts as it becomes the selected one, and the whole thing
          // dips under the finger. Anything louder than this on a control
          // people press forty times a day stops being feedback and starts
          // being an interruption. Every one of them is skipped when the
          // system asks for reduced motion.
          return Expanded(
            child: PressableScale(
              scale: 0.93,
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: Dur.quick,
                curve: Ease.standard,
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: on ? SC.blueBright : Colors.transparent,
                  borderRadius: BorderRadius.circular(SC.rPill),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedScale(
                          scale: on ? 1.14 : 1,
                          duration: Dur.quick,
                          // A little overshoot on the way in, so the icon
                          // settles rather than simply arriving.
                          curve: on ? Ease.pop : Ease.standard,
                          child: AnimatedSwitcher(
                            duration: Dur.micro,
                            child: Icon(
                              it.icon,
                              key: ValueKey(on),
                              size: 22,
                              color: on ? Colors.white : SC.inkFaint,
                            ),
                          ),
                        ),
                        if (it.dot)
                          Positioned(
                            right: -3,
                            top: -2,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: SC.gold,
                                shape: BoxShape.circle,
                                border: Border.all(color: on ? SC.blueBright : SC.surface, width: 1.4),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    AnimatedDefaultTextStyle(
                      duration: Dur.quick,
                      curve: Ease.standard,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: on ? Colors.white : SC.inkFaint,
                      ),
                      child: Text(t(it.label), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// JOURNEY STEPPER
// ---------------------------------------------------------------------------

class JourneyStep {
  const JourneyStep(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// The "Booking Journey — Step 4 of 6" card. [current] is zero-based; every
/// step before it renders as done.
class JourneyStepper extends StatelessWidget {
  const JourneyStepper({
    super.key,
    required this.steps,
    required this.current,
    this.title = 'Booking Journey',
  });

  final List<JourneyStep> steps;
  final int current;
  final String title;

  @override
  Widget build(BuildContext context) {
    final pct = steps.isEmpty ? 0.0 : ((current + 1) / steps.length).clamp(0.0, 1.0);
    return SCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: SC.brandGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.route_rounded, color: Colors.white, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t(title), style: ST.h2),
                    Text(t('Step {n} of {total}',
                        {'n': current + 1, 'total': steps.length}),
                        style: ST.small),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: SC.blueTint,
                  borderRadius: BorderRadius.circular(SC.rPill),
                ),
                child: Text('${(pct * 100).round()}%',
                    style: const TextStyle(
                        color: SC.blueLink, fontWeight: FontWeight.w800, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(SC.rPill),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: SC.hairline,
              valueColor: const AlwaysStoppedAnimation(SC.green),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(steps.length, (i) {
              final done = i < current;
              final now = i == current;
              return Expanded(
                child: Column(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: now
                            ? SC.navy
                            : done
                                ? SC.greenTint
                                : SC.hairline,
                        border: Border.all(
                          color: now
                              ? SC.navy
                              : done
                                  ? SC.green
                                  : SC.hairline,
                          width: 1.6,
                        ),
                      ),
                      child: Icon(
                        done ? Icons.check_rounded : steps[i].icon,
                        size: 17,
                        color: now
                            ? Colors.white
                            : done
                                ? SC.green
                                : SC.inkFaint,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t(steps[i].label),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                        color: now
                            ? SC.navy
                            : done
                                ? SC.green
                                : SC.inkFaint,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// EMPTY / LOADING / ERROR
// ---------------------------------------------------------------------------

/// Shown wherever a list can legitimately be empty. Every list in the app
/// routes through this rather than rendering nothing, so "no data" always
/// looks deliberate instead of broken.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_rounded,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final String title;
  final String? message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: compact ? 26 : 44, horizontal: 24),
      decoration: BoxDecoration(
        color: SC.white,
        borderRadius: BorderRadius.circular(SC.rCard),
        border: Border.all(color: SC.hairline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: SC.blueTint,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, size: 29, color: SC.blueBright),
          ),
          const SizedBox(height: 16),
          Text(t(title), textAlign: TextAlign.center, style: ST.h3),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, textAlign: TextAlign.center, style: ST.body),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: 210,
              child: ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                child: Text(actionLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A shimmer-free loading placeholder that matches the card geometry, so the
/// page does not jump when the real content lands.
class LoadingCards extends StatelessWidget {
  const LoadingCards({super.key, this.count = 3, this.height = 96});
  final int count;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        count,
        (i) => Container(
          height: height,
          margin: EdgeInsets.only(bottom: i == count - 1 ? 0 : 12),
          decoration: BoxDecoration(
            color: SC.white.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(SC.rCard),
            border: Border.all(color: SC.hairline),
          ),
          child: const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: SC.inkFaint),
            ),
          ),
        ),
      ),
    );
  }
}

class InlineError extends StatelessWidget {
  const InlineError({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFCE9EA),
        borderRadius: BorderRadius.circular(SC.rCard),
        border: Border.all(color: const Color(0xFFF2C7CA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline_rounded, color: SC.redDeep, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(message,
                    style: const TextStyle(
                        color: SC.redDeep, fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.4)),
              ),
            ],
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: Text(t('Try again')),
                style: TextButton.styleFrom(foregroundColor: SC.redDeep),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// BUTTONS
// ---------------------------------------------------------------------------

/// The full-width gradient action. A plain ElevatedButton is flat blue; this
/// is the one that carries the brand gradient, used for the single primary
/// action on a screen.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.busy = false,
    this.height = 56,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: SC.brandGradient,
          borderRadius: BorderRadius.circular(SC.rField),
          boxShadow: enabled ? SC.cardShadow : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[Icon(icon, color: Colors.white, size: 20), const SizedBox(width: 9)],
                        Text(t(label),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// MISC
// ---------------------------------------------------------------------------

class StarRating extends StatelessWidget {
  const StarRating({super.key, required this.value, this.size = 15, this.showValue = true, this.count});
  final double value;
  final double size;
  final bool showValue;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: size + 2, color: SC.gold),
        if (showValue) ...[
          const SizedBox(width: 3),
          Text(value.toStringAsFixed(1),
              style: TextStyle(fontSize: size - 1, fontWeight: FontWeight.w800, color: SC.ink)),
        ],
        if (count != null) ...[
          const SizedBox(width: 4),
          Text(t('({count}+ reviews)', {'count': count}),
              style: ST.small.copyWith(fontSize: size - 2.5)),
        ],
      ],
    );
  }
}

/// Tappable 1-5 stars for leaving a rating.
class StarPicker extends StatelessWidget {
  const StarPicker({super.key, required this.value, required this.onChanged, this.size = 40});
  final int value;
  final ValueChanged<int> onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (i) {
        final on = i < value;
        return IconButton(
          onPressed: () => onChanged(i + 1),
          iconSize: size,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          constraints: const BoxConstraints(),
          icon: Icon(
            on ? Icons.star_rounded : Icons.star_border_rounded,
            color: on ? SC.gold : SC.hairlineCool,
          ),
        );
      }),
    );
  }
}

/// A row of key/value lines inside a dark card — the bill summary.
class SummaryRow extends StatelessWidget {
  const SummaryRow(this.label, this.value, {super.key, this.emphasis = false});
  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(t(label),
                style: TextStyle(
                  color: emphasis ? Colors.white : Colors.white70,
                  fontSize: emphasis ? 15 : 14,
                  fontWeight: emphasis ? FontWeight.w700 : FontWeight.w400,
                )),
          ),
          Text(value,
              style: TextStyle(
                color: Colors.white,
                fontSize: emphasis ? 17 : 14.5,
                fontWeight: emphasis ? FontWeight.w800 : FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ],
      ),
    );
  }
}

/// Dashed separator for the bill summary.
class DashedDivider extends StatelessWidget {
  const DashedDivider({super.key, this.color = Colors.white24});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final n = math.max(1, (c.maxWidth / 8).floor());
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(
          n,
          (_) => SizedBox(width: 4, height: 1, child: DecoratedBox(decoration: BoxDecoration(color: color))),
        ),
      );
    });
  }
}

/// Standard page padding — matches the reference gutter everywhere.
class PagePad extends StatelessWidget {
  const PagePad({super.key, required this.child, this.top = 16, this.bottom = 24});
  final Widget child;
  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: EdgeInsets.fromLTRB(SC.gutter, top, SC.gutter, bottom), child: child);
}
