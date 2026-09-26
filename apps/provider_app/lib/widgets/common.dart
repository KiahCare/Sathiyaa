import 'dart:io';

import 'package:flutter/material.dart';
import 'osm_map.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../backend.dart';
import '../i18n/l10n.dart';

const kPrimaryColor = Color(0xFF0B5ED7);

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

class StatTile extends StatelessWidget {
  final String label;
  final String value;
  const StatTile({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: kPrimaryColor.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kPrimaryColor)),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
      ),
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

/// Turn-by-turn stand-in for the "Show Direction" requirement: provider's
/// current position, the customer's address, and the straight-line distance
/// between them. A real Google Directions call would replace the body here.
class DirectionsPanel extends StatelessWidget {
  final double fromLat;
  final double fromLng;
  final double toLat;
  final double toLng;
  final String destination;
  final double distanceKm;
  const DirectionsPanel({
    super.key,
    required this.fromLat,
    required this.fromLng,
    required this.toLat,
    required this.toLng,
    required this.destination,
    required this.distanceKm,
  });

  @override
  Widget build(BuildContext context) {
    final etaMinutes = (distanceKm / 25 * 60).clamp(1, 999).round(); // ~25 km/h city average
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MapPlaceholder(lat: toLat, lng: toLng, label: destination, height: 140),
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(Icons.my_location, size: 16, color: Colors.black54),
            const SizedBox(width: 8),
            Expanded(
                child: Text(t('You: {lat}, {lng}', {
              'lat': fromLat.toStringAsFixed(4),
              'lng': fromLng.toStringAsFixed(4),
            }))),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(Icons.flag_outlined, size: 16, color: Colors.black54),
            const SizedBox(width: 8),
            Expanded(child: Text(destination)),
          ],
        ),
        const Divider(height: 20),
        Text(
          '${distanceKm.toStringAsFixed(1)} km · about $etaMinutes min',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          t('Straight-line estimate. Live routing arrives with the Google Maps integration.'),
          style: const TextStyle(fontSize: 11, color: Colors.black54),
        ),
      ],
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
