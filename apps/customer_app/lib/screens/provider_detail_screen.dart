// The provider's profile — where a family decides.
//
// Rebuilt on the design system. The order follows the question being asked:
// who is this person, can I trust them, what do they cost, where are they,
// and then the two things you can do about it.
//
// The link toggle and the booking hand-off are unchanged.

import 'package:flutter/material.dart';

import '../backend.dart';
import '../models.dart';
import '../theme/sathiyaa_theme.dart';
import '../widgets/sathiyaa_ui.dart';
import '../widgets/motion.dart';
import '../widgets/osm_map.dart';
import '../widgets/common.dart' show avatarImage;
import 'booking_flow.dart';
import '../i18n/l10n.dart';

class ProviderDetailScreen extends StatefulWidget {
  final String providerId;
  final BookingCriteria criteria;

  const ProviderDetailScreen({
    super.key,
    required this.providerId,
    required this.criteria,
  });

  @override
  State<ProviderDetailScreen> createState() => _ProviderDetailScreenState();
}

class _ProviderDetailScreenState extends State<ProviderDetailScreen> {
  Provider? provider;
  String? error;
  bool linking = false;

  @override
  void initState() {
    super.initState();
    provider = Backend.instance.cachedProvider(widget.providerId);
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await Backend.instance.providerById(widget.providerId);
      if (mounted) setState(() => provider = p);
    } catch (e) {
      // A cached copy from the search results is good enough to render; only
      // surface the failure when there is nothing to show at all.
      if (mounted && provider == null) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  bool get isLinked =>
      Backend.instance.currentCustomer?.linkedProviderIds.contains(widget.providerId) ??
      false;

  Future<void> toggleLink() async {
    final messenger = ScaffoldMessenger.of(context);
    final wasLinked = isLinked;
    setState(() => linking = true);
    try {
      if (wasLinked) {
        await Backend.instance.unlinkProvider(widget.providerId);
      } else {
        await Backend.instance.linkProvider(widget.providerId);
      }
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text(wasLinked
              ? 'Removed from your regular carers.'
              : 'Saved to your regular carers.'),
        ));
      }
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => linking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = provider;

    if (p == null) {
      return Scaffold(
        backgroundColor: SC.paper,
        body: Column(
          children: [
            BrandHeader(
              curved: false,
              child: BrandBar(
                title: t('Profile'),
                onBack: () => Navigator.of(context).pop(),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(SC.gutter),
                child: error == null
                    ? const SkeletonList(count: 3)
                    : InlineError(message: error!, onRetry: _load),
              ),
            ),
          ],
        ),
      );
    }

    final linkedCount = Backend.instance.currentCustomer?.linkedProviderIds.length ?? 0;
    final atCap = !isLinked && linkedCount >= 10;

    return Scaffold(
      backgroundColor: SC.paper,
      body: Column(
        children: [
          _header(p),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(SC.gutter, 18, SC.gutter, 24),
              children: staggered([
                _trustCard(p),
                const SizedBox(height: 14),
                _rateCard(p),
                if (p.expertise.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  SectionLabel(t('Care they can give')),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: p.expertise.map((e) => SkillTag(e.label)).toList(),
                  ),
                ],
                if (p.languages.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  SectionLabel(t('Languages')),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: p.languages.map((l) => SkillTag(l)).toList(),
                  ),
                ],
                if (p.lat != 0 || p.lng != 0) ...[
                  const SizedBox(height: 22),
                  SectionLabel(t('Where they work from')),
                  OsmMap(
                    lat: p.lat,
                    lng: p.lng,
                    label: p.city.isEmpty ? p.name : p.city,
                    height: 160,
                  ),
                ],
                const SizedBox(height: 26),
                GradientButton(
                  label: t('Send a request'),
                  icon: Icons.send_rounded,
                  onPressed: () => push(
                    context,
                    BookingConfirmScreen(providerIds: [p.id], criteria: widget.criteria),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: linking || atCap ? null : toggleLink,
                  icon: Icon(
                    isLinked ? Icons.bookmark_remove_rounded : Icons.bookmark_add_rounded,
                    size: 18,
                  ),
                  label: Text(isLinked
                      ? 'Remove from my regular carers'
                      : 'Save to my regular carers ($linkedCount/10)'),
                ),
                if (atCap)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      t('You already have ten regular carers saved. Remove one first.'),
                      textAlign: TextAlign.center,
                      style: ST.small,
                    ),
                  ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    t('Nothing is charged for sending a request. You only pay once somebody accepts.'),
                    textAlign: TextAlign.center,
                    style: ST.small,
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(Provider p) {
    return BrandHeader(
      curved: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, SC.gutter, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 30),
                ),
                const Spacer(),
                if (isLinked)
                  StatusChip(t('Regular carer'), tone: ChipTone.gold, dense: true),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 14, top: 4, bottom: 6),
              child: Row(
                children: [
                  InitialsAvatar(
                    name: p.name,
                    size: 72,
                    radius: 22,
                    image: avatarImage(p.photoUrl),
                    badge: p.approved ? Icons.verified_rounded : null,
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.star_rounded, size: 17, color: SC.gold),
                            const SizedBox(width: 3),
                            Text(
                              p.ratingAvg.toStringAsFixed(1),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(width: 5),
                            Text('(${p.ratingCount})',
                                style: const TextStyle(color: Colors.white70, fontSize: 13)),
                            if (p.distanceKm != null) ...[
                              const SizedBox(width: 12),
                              const Icon(Icons.place_rounded, size: 15, color: Colors.white70),
                              const SizedBox(width: 3),
                              Text('${p.distanceKm!.toStringAsFixed(1)} km',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 13)),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// What "verified" actually means, spelled out. A tick nobody can explain is
  /// worth nothing to a family deciding who to let into the house.
  Widget _trustCard(Provider p) {
    if (!p.approved) {
      return SCard(
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: SC.amberTint,
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(Icons.hourglass_empty_rounded,
                  color: Color(0xFFA9670F), size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(t('Sathiyaa is still checking this person’s papers.'),
                  style: ST.body),
            ),
          ],
        ),
      );
    }

    return SCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: SC.greenTint,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.verified_user_rounded, color: SC.green, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(t('Checked by Sathiyaa'), style: ST.h3)),
            ],
          ),
          const SizedBox(height: 12),
          _check('Identity document on file'),
          _check('Police verification on file'),
          if (p.expertise.any(
              (e) => e == ServiceType.nurse || e == ServiceType.physiotherapy))
            _check('Medical certificate on file'),
        ],
      ),
    );
  }

  Widget _check(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, size: 16, color: SC.green),
          const SizedBox(width: 9),
          Expanded(child: Text(text, style: ST.body.copyWith(fontSize: 13.5))),
        ],
      ),
    );
  }

  Widget _rateCard(Provider p) {
    if (p.noFees) {
      return DarkCard(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF14503C), Color(0xFF2E9E5B)],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('Gives their time free'),
                      style: const TextStyle(
                          color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(t('You will not be charged for their visits.'),
                      style: const TextStyle(color: Colors.white70, fontSize: 13.5)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final hours = widget.criteria.totalHours;
    final estimate = (p.hourlyRate ?? 0) * hours;

    return SCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('₹${p.hourlyRate?.toStringAsFixed(0) ?? '—'}',
                  style: ST.figure.copyWith(fontSize: 30)),
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 6),
                child: Text(t('per hour'), style: ST.body),
              ),
            ],
          ),
          if (hours > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SC.sunkTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long_rounded, size: 17, color: SC.inkFaint),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'About ₹${estimate.toStringAsFixed(0)} for the '
                      '${hours.toStringAsFixed(1)} hours you asked for — billed on the '
                      'hours actually worked, and settled after the visit.',
                      style: ST.small.copyWith(height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
