import 'dart:io';
import '../theme/sathiyaa_theme.dart';

import 'package:flutter/material.dart';
import 'osm_map.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../backend.dart';
import '../i18n/l10n.dart';

const kPrimaryColor = Color(0xFF1A7F37);

class SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;
  const SectionCard({super.key, required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  const PrimaryButton({super.key, required this.label, required this.onPressed, this.loading = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        child: loading
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(label),
      ),
    );
  }
}

class CapCounter extends StatelessWidget {
  final int count;
  final int cap;
  const CapCounter({super.key, required this.count, required this.cap});

  @override
  Widget build(BuildContext context) {
    final atCap = count >= cap;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: atCap ? Colors.red.shade50 : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('$count/$cap', style: TextStyle(color: atCap ? Colors.red.shade700 : Colors.black87, fontWeight: FontWeight.w600)),
    );
  }
}

class RatingStars extends StatelessWidget {
  final double rating;
  final double size;
  const RatingStars({super.key, required this.rating, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < rating.round();
        return Icon(filled ? Icons.star : Icons.star_border, color: Colors.amber, size: size);
      }),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  final String message;
  const ErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
      child: Text(message, style: TextStyle(color: Colors.red.shade800)),
    );
  }
}

/// The one-time code, shown on screen because no SMS provider is wired up yet.
///
/// The code itself is random and server-issued — this only displays it. When a
/// real SMS gateway is configured the server stops returning it here and this
/// never renders.
class DevOtpBanner extends StatelessWidget {
  final String otp;

  /// Fills the code into the field for you. It is on screen and it is six
  /// digits; making somebody copy it across by hand is a small insult.
  final VoidCallback? onUse;

  const DevOtpBanner({super.key, required this.otp, this.onUse});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: SC.goldTint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEDCB6)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('YOUR CODE — NO SMS IS SENT YET'),
                    style: ST.label.copyWith(color: const Color(0xFF8A6317))),
                const SizedBox(height: 5),
                Text(otp,
                    style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 8,
                      color: Color(0xFF6B4A0C),
                    )),
              ],
            ),
          ),
          if (onUse != null)
            TextButton(
              onPressed: onUse,
              style: TextButton.styleFrom(foregroundColor: const Color(0xFF8A6317)),
              child: Text(t('Use it')),
            ),
        ],
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  final String text;
  final Color color;
  const StatusPill({super.key, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

/// The address/location panel used across the app.
///
/// This used to be a grey rectangle labelled "Maps stub" that only printed the
/// coordinates. It now draws a real OpenStreetMap — free, no key, no account —
/// and keeps the same name and constructor so every screen that already showed
/// a location got a map without being rewritten. See widgets/osm_map.dart.
class MapPlaceholder extends StatelessWidget {
  final double lat;
  final double lng;
  final String label;
  final double height;
  const MapPlaceholder({super.key, required this.lat, required this.lng, required this.label, this.height = 120});

  @override
  Widget build(BuildContext context) =>
      OsmMap(lat: lat, lng: lng, label: label, height: height);
}

/// Expand/collapse wrapper used by the profile screen. The requirements doc
/// asks specifically for Insurance, Family, Allergy, Surgery, Medication and
/// Vitals to be collapsible, so they all render through this.
class ExpandableSection extends StatefulWidget {
  final String title;
  final String badge;
  final bool initiallyExpanded;
  final List<Widget> children;
  final IconData icon;

  const ExpandableSection({
    super.key,
    required this.title,
    required this.badge,
    required this.children,
    this.initiallyExpanded = false,
    this.icon = Icons.folder_rounded,
  });

  @override
  State<ExpandableSection> createState() => _ExpandableSectionState();
}

class _ExpandableSectionState extends State<ExpandableSection> {
  late bool open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    // Hand-rolled rather than an ExpansionTile: the tile insists on its own
    // Material, its own divider colours and a trailing slot only as wide as it
    // feels like giving, which is what pushed the count into the title before.
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: SC.surface,
        borderRadius: BorderRadius.circular(SC.rCard),
        border: Border.all(color: open ? SC.blueBright : SC.hairline, width: open ? 1.5 : 1),
        boxShadow: SC.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => open = !open),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: open ? SC.blueTint : SC.sunkTint,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(widget.icon,
                          size: 19, color: open ? SC.blueBright : SC.inkSoft),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(widget.title,
                          style: ST.h3, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: SC.sunkTint,
                        borderRadius: BorderRadius.circular(SC.rPill),
                      ),
                      child: Text(widget.badge,
                          style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: SC.inkSoft)),
                    ),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(Icons.expand_more_rounded, color: SC.inkFaint),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: widget.children,
                ),
              ),
              crossFadeState:
                  open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
              sizeCurve: Curves.easeOutCubic,
            ),
          ],
        ),
      ),
    );
  }
}

/// Profile and document images arrive in three shapes: an absolute URL, a
/// path the server serves relative to itself (`/uploads/...`, which is what
/// the upload endpoint returns), or a local file path from the picker before
/// anything has been sent. This resolves all three, or gives null when there
/// is nothing to show.
///
/// The relative case used to be missing, so every photo that had actually
/// been uploaded displayed as blank -- the one shape the real server produces.
ImageProvider? avatarImage(String? ref) {
  if (ref == null || ref.isEmpty) return null;
  if (ref.startsWith('http://') || ref.startsWith('https://')) return NetworkImage(ref);

  final resolved = Backend.instance.absoluteUrl(ref);
  if (resolved != null) return NetworkImage(resolved);

  // dart:io has no File on the web, and touching it there throws rather than
  // returning false.
  if (kIsWeb) return null;
  final file = File(ref);
  return file.existsSync() ? FileImage(file) : null;
}

/// Whether there is an image to render at all, without building the provider.
bool hasImage(String? ref) => avatarImage(ref) != null;
