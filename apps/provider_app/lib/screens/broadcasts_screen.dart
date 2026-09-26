import 'package:flutter/material.dart';

import '../backend.dart';
import '../broadcasts.dart';
import '../theme/sathiyaa_theme.dart';
import '../widgets/motion.dart';
import '../widgets/sathiyaa_ui.dart';
import '../i18n/l10n.dart';
import '../utils/dates.dart';

/// Messages Sathiyaa has sent to carers.
///
/// The console could send these before anything could receive them: the
/// broadcast was written, the recipients were written, the count was
/// reported, and no screen in either app ever asked the server what had been
/// sent. This is the asking.
///
/// Opening the screen is what reading them is — there is no "mark as read"
/// button, because a message you have just looked at does not need one.
class BroadcastsScreen extends StatefulWidget {
  const BroadcastsScreen({super.key});

  @override
  State<BroadcastsScreen> createState() => _BroadcastsScreenState();
}

class _BroadcastsScreenState extends State<BroadcastsScreen> {
  List<Broadcast> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await Backend.instance.loadBroadcasts();
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
        _loading = false;
      });
      if (items.any((i) => !i.read)) {
        // Fire and forget. A failure here leaves the badge wrong for a while,
        // which is not worth interrupting anybody over.
        Backend.instance.markBroadcastsRead().catchError((_) {});
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SC.paper,
      body: Column(
        children: [
          BrandHeader(
            curved: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, SC.gutter, 14),
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
                        Text(t('From Sathiyaa'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(t('Notices sent to everybody who works with us'),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: SizedBox(
            width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4)),
      );
    }
    if (_error != null) {
      return Center(
        child: PagePad(
          child: EmptyState(
            icon: Icons.wifi_off_rounded,
            title: t('Could not load your messages'),
            message: _error!,
            actionLabel: t('Try again'),
            onAction: () {
              setState(() => _loading = true);
              _load();
            },
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: PagePad(
          child: EmptyState(
            icon: Icons.campaign_rounded,
            title: t('Nothing yet'),
            message: t('When Sathiyaa sends a notice to carers, it will be here.'),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(SC.gutter, 18, SC.gutter, 32),
      children: staggered([for (final b in _items) _card(b)]),
    );
  }

  Widget _card(Broadcast b) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: b.read ? SC.sunkTint : SC.blueTint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.campaign_rounded,
                      size: 19, color: b.read ? SC.inkFaint : SC.blueBright),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(b.title, style: ST.h3),
                      const SizedBox(height: 3),
                      Text(prettyDate(b.sentAt), style: ST.small.copyWith(fontSize: 12)),
                    ],
                  ),
                ),
                if (!b.read)
                  Container(
                    width: 9,
                    height: 9,
                    margin: const EdgeInsets.only(top: 6),
                    decoration: const BoxDecoration(
                        color: SC.blueBright, shape: BoxShape.circle),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(b.message, style: ST.body.copyWith(height: 1.5)),
          ],
        ),
      ),
    );
  }
}
