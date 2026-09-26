import 'package:flutter/material.dart';

import '../backend.dart';
import '../models.dart';
import '../theme/sathiyaa_theme.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';
import '../widgets/sathiyaa_ui.dart';
import '../i18n/l10n.dart';

/// The carers the customer has saved, capped at 10 by the spec.
///
/// Rebuilt on the design system. Two things changed besides the look: the
/// screen is called what the profile calls it — "My regular carers", not "My
/// providers" — and unlinking asks first. It was a single tap on a small red
/// icon, with no undo, on the list of people you trust.
class LinkedProvidersScreen extends StatefulWidget {
  const LinkedProvidersScreen({super.key});

  @override
  State<LinkedProvidersScreen> createState() => _LinkedProvidersScreenState();
}

class _LinkedProvidersScreenState extends State<LinkedProvidersScreen> {
  late Future<List<Provider>> _future = Backend.instance.linkedProviders();

  void _reload() => setState(() => _future = Backend.instance.linkedProviders());

  Future<void> _unlink(Provider p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: SC.surface,
        title: Text(t('Remove this carer?'), style: ST.h2),
        content: Text(
          '${p.name} comes off your regular list. You can still find them in '
          'search and save them again.',
          style: ST.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('Keep them')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: SC.red),
            child: Text(t('Remove')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await Backend.instance.unlinkProvider(p.id);
      if (!mounted) return;
      _reload();
      messenger.showSnackBar(SnackBar(content: Text(t('{name} removed.', {'name': p.name}))));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = Backend.instance.currentCustomer?.linkedProviderIds.length ?? 0;
    return Scaffold(
      backgroundColor: SC.paper,
      body: Column(
        children: [
          BrandHeader(
            curved: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, SC.gutter, 16),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.chevron_left_rounded,
                        color: Colors.white, size: 30),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t('My regular carers'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(t('People you would have back'),
                            style: const TextStyle(color: Colors.white70, fontSize: 13.5)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(SC.rPill),
                    ),
                    child: Text(t('{count} of 10', {'count': count}),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Provider>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const PagePad(top: 20, child: SkeletonList(count: 4));
                }
                if (snap.hasError) {
                  return PagePad(
                    top: 20,
                    child: InlineError(
                      message: snap.error.toString().replaceFirst('Exception: ', ''),
                      onRetry: _reload,
                    ),
                  );
                }
                final providers = snap.data ?? const <Provider>[];
                if (providers.isEmpty) {
                  return Center(
                    child: PagePad(
                      child: EmptyState(
                        icon: Icons.bookmark_border_rounded,
                        title: t('No regular carers yet'),
                        message: t('When somebody looks after you well, open their profile and save them. They appear here, so booking them again takes two taps instead of a search.'),
                      ),
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(SC.gutter, 18, SC.gutter, 30),
                  children: staggered([
                    for (final p in providers) _card(p),
                    const SizedBox(height: 10),
                    Text(
                      t('You can save up to 10. Removing somebody here does not affect a booking that is already made.'),
                      style: ST.small.copyWith(fontSize: 12, height: 1.45),
                    ),
                  ]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(Provider p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InitialsAvatar(
              name: p.name,
              size: 48,
              radius: 15,
              image: avatarImage(p.photoUrl),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name,
                      style: ST.h3, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      StarRating(value: p.ratingAvg, count: p.ratingCount, size: 13),
                      const SizedBox(width: 10),
                      if (p.noFees)
                        StatusChip(t('Volunteer'), tone: ChipTone.gold, dense: true)
                      else
                        Text('₹${p.hourlyRate?.toStringAsFixed(0) ?? '—'}/hr',
                            style: ST.bodyStrong.copyWith(fontSize: 13)),
                    ],
                  ),
                  if (p.expertise.isNotEmpty) ...[
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final e in p.expertise.take(3)) SkillTag(e.label),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.bookmark_remove_rounded, color: SC.red),
              tooltip: t('Remove from my carers'),
              onPressed: () => _unlink(p),
            ),
          ],
        ),
      ),
    );
  }
}
