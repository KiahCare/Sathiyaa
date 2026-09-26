// Finding a companion.
//
// The spec asks for date duration, time and location as search inputs, not
// just a service type, so all three are here and the resulting
// `BookingCriteria` follows the customer all the way into the booking rather
// than being thrown away.
//
// Rebuilt on the design system. Two changes worth naming: the care type is a
// row of tappable cards instead of a dropdown, because it is the single most
// important choice on the screen and a dropdown hides it; and results can be
// sorted, because "nearest" is not always what somebody wants.

import 'package:flutter/material.dart';

import '../models.dart';
import '../backend.dart';
import '../mock_data.dart';
import '../theme/sathiyaa_theme.dart';
import '../widgets/sathiyaa_ui.dart';
import '../widgets/motion.dart';
import '../widgets/common.dart' show avatarImage;
import 'provider_detail_screen.dart';
import 'booking_flow.dart';
import '../city_defaults.dart';
import '../languages.dart';
import '../i18n/l10n.dart';

enum SortBy { distance, rating, priceLow }

extension _SortLabel on SortBy {
  String get label => switch (this) {
        SortBy.distance => t('Nearest'),
        SortBy.rating => t('Best rated'),
        SortBy.priceLow => t('Lowest rate'),
      };
  IconData get icon => switch (this) {
        SortBy.distance => Icons.near_me_rounded,
        SortBy.rating => Icons.star_rounded,
        SortBy.priceLow => Icons.currency_rupee_rounded,
      };
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  ServiceType type = ServiceType.companion;
  String gender = 'Any';
  String language = 'Any';
  DateTime startDate = DateTime.now().add(const Duration(days: 1));
  DateTime endDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay timeFrom = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay timeTo = const TimeOfDay(hour: 14, minute: 0);
  double radiusKm = 25;
  Address? location;
  SortBy sort = SortBy.distance;

  /// Who the visit is for. Null is the account holder, and is the default
  /// because it is the common case — but an adult child arranging care for a
  /// parent is the case this app exists for, and before this there was no way
  /// to say so. The carer arrived asking for the wrong person.
  FamilyMember? forMember;

  bool searched = false;
  bool loading = false;
  String? error;
  List<Provider> results = [];

  /// Carers picked to ask together. The request goes to all of them at once and
  /// the first to accept takes the visit — which is what the server has always
  /// done internally, and is now something the customer decides rather than
  /// something that happens to them.
  ///
  /// Kept as ids rather than objects so a fresh search does not lose a
  /// selection, and cleared when the criteria change, because a carer who was
  /// free on Tuesday is not necessarily free on Thursday.
  final Set<String> chosen = {};

  /// Whether the list is in "pick several" mode.
  ///
  /// Before this, asking several carers at once was possible but invisible:
  /// there was a 26px tick on the corner of each avatar and nothing that said
  /// what it was for. Somebody who wanted one carer kept catching it by
  /// accident, and somebody who wanted four never found it. So the choice is
  /// now made once, in words, above the list -- and it changes what a tap on
  /// a card means, which is the part that makes picking four people quick.
  bool askSeveral = false;

  void _toggle(Provider p) => setState(() {
        if (!chosen.remove(p.id)) chosen.add(p.id);
      });

  /// Anything that changes who is eligible invalidates the shortlist.
  void _clearChoiceOnCriteriaChange() {
    if (chosen.isNotEmpty) chosen.clear();
  }

  @override
  void initState() {
    super.initState();
    location = Backend.instance.primaryAddress();
    runSearch();
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  BookingCriteria get criteria => BookingCriteria(
        serviceType: type,
        startDate: startDate,
        endDate: endDate,
        timeFrom: _fmt(timeFrom),
        timeTo: _fmt(timeTo),
        lat: location?.lat ?? kDefaultLat,
        lng: location?.lng ?? kDefaultLng,
        locationLabel: location == null
            ? kDefaultCity
            : '${location!.line1}, ${location!.city}',
        forMember: forMember,
      );

  /// The people on this account a visit can be booked for.
  List<FamilyMember> get _family =>
      Backend.instance.currentCustomer?.family
          .where((f) => f.active)
          .toList() ??
      const <FamilyMember>[];

  /// "Who is this for?"
  ///
  /// Only shown when there is somebody to choose. With no family members on
  /// the account the question has one possible answer, and a control with one
  /// option is furniture.
  Widget _forWhom() {
    final family = _family;
    if (family.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FieldLabel(t('Who is this for')),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _forChip(
                label: t('Myself'),
                icon: Icons.person_rounded,
                on: forMember == null,
                onTap: () => setState(() => forMember = null),
              ),
              for (final f in family)
                _forChip(
                  label: f.name,
                  sub: f.relationship,
                  icon: Icons.favorite_rounded,
                  on: forMember?.id == f.id,
                  onTap: () => setState(() => forMember = f),
                ),
            ],
          ),
          if (forMember != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 2),
              child: Text(
                t('The carer will be told they are visiting {name}, and will have a number to reach them on.',
                    {'name': forMember!.name}),
                style: ST.small.copyWith(fontSize: 12, height: 1.4),
              ),
            ),
        ],
      ),
    );
  }

  Widget _forChip({
    required String label,
    required IconData icon,
    required bool on,
    required VoidCallback onTap,
    String? sub,
  }) {
    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Dur.quick,
        curve: Ease.enter,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: on ? SC.blueBright : SC.surface,
          borderRadius: BorderRadius.circular(SC.rPill),
          border: Border.all(
              color: on ? SC.blueBright : SC.hairlineCool, width: 1.3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: on ? Colors.white : SC.inkFaint),
            const SizedBox(width: 7),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: on ? Colors.white : SC.inkSoft,
                    )),
                if (sub != null)
                  Text(sub,
                      style: TextStyle(
                        fontSize: 11,
                        color: on ? Colors.white70 : SC.inkFaint,
                      )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  double _km(Provider p) =>
      p.distanceKm ??
      MockBackend.distanceKm(criteria.lat, criteria.lng, p.lat, p.lng);

  List<Provider> get _sorted {
    final list = [...results];
    switch (sort) {
      case SortBy.distance:
        list.sort((a, b) => _km(a).compareTo(_km(b)));
      case SortBy.rating:
        list.sort((a, b) => b.ratingAvg.compareTo(a.ratingAvg));
      case SortBy.priceLow:
        // No-fee volunteers sort to the top; they cost nothing.
        double rate(Provider p) => p.noFees ? -1 : (p.hourlyRate ?? 1e9);
        list.sort((a, b) => rate(a).compareTo(rate(b)));
    }
    return list;
  }

  Future<void> runSearch() async {
    setState(() {
      loading = true;
      error = null;
      // A new search is a new question. Keeping a shortlist across it would let
      // somebody carry a carer from Tuesday's results into Thursday's booking,
      // and the server would refuse them with no explanation the app could give.
      _clearChoiceOnCriteriaChange();
    });
    try {
      final r = await Backend.instance.search(
        type: type,
        gender: gender,
        language: language,
        dateFrom: startDate,
        dateTo: endDate,
        timeFrom: _fmt(timeFrom),
        timeTo: _fmt(timeTo),
        lat: location?.lat,
        lng: location?.lng,
        radiusKm: radiusKm,
      );
      if (!mounted) return;
      setState(() {
        results = r;
        searched = true;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = '$e'.replaceFirst('Exception: ', '');
        searched = true;
        loading = false;
      });
    }
  }

  // ---- pickers --------------------------------------------------------

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: startDate, end: endDate),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        startDate = picked.start;
        endDate = picked.end;
      });
    }
  }

  Future<void> _pickTime({required bool from}) async {
    final picked = await showTimePicker(
        context: context, initialTime: from ? timeFrom : timeTo);
    if (picked == null) return;
    setState(() => from ? timeFrom = picked : timeTo = picked);
  }

  Future<void> _pickLocation() async {
    final addresses =
        Backend.instance.currentCustomer?.addresses ?? const <Address>[];
    if (addresses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('Add an address in your profile first.'))),
      );
      return;
    }
    final chosen = await showModalBottomSheet<Address>(
      context: context,
      backgroundColor: SC.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                  color: SC.hairlineCool,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(t('Where is the care needed?'), style: ST.h2),
              ),
            ),
            ...addresses.map(
              (a) => ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: SC.blueTint,
                      borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.place_rounded,
                      color: SC.blueBright, size: 20),
                ),
                title: Text(a.label, style: ST.h3),
                subtitle: Text('${a.line1}, ${a.city}', style: ST.small),
                onTap: () => Navigator.pop(context, a),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (chosen != null) setState(() => location = chosen);
  }

  // ---- build ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = criteria;

    return Scaffold(
      backgroundColor: SC.paper,
      body: Column(
        children: [
          BrandHeader(
            curved: false,
            child: BrandBar(
              title: t('Find care'),
              subtitle: searched && error == null
                  ? '${results.length} available near you'
                  : 'Companions and nurses near you',
              actions: [
                HeaderIconButton(
                  icon: Icons.refresh_rounded,
                  tooltip: t('Search again'),
                  onTap: runSearch,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(SC.gutter, 18, SC.gutter, 110),
              children: [
                _careTypes(),
                const SizedBox(height: 20),
                // Before the dates: who the visit is for changes what a
                // sensible answer to everything below it looks like.
                _forWhom(),
                _whenAndWhere(c),
                const SizedBox(height: 16),
                _preferences(),
                const SizedBox(height: 18),
                GradientButton(
                  label: t('Search'),
                  icon: Icons.search_rounded,
                  busy: loading,
                  onPressed: loading ? null : runSearch,
                ),
                const SizedBox(height: 26),
                _resultsHeader(c),
                _askMode(),
                const SizedBox(height: 12),
                FadeSwitch(child: _results(c)),
              ],
            ),
          ),
        ],
      ),
      // Sits above the nav bar and only exists once somebody has been picked,
      // so the screen is unchanged for anyone who just wants one carer.
      bottomNavigationBar: _askBar(c),
    );
  }

  /// How the request goes out: to one carer, or to several at once.
  ///
  /// Sits directly above the list because it changes what tapping a card in
  /// that list does, and a control whose effect is somewhere else on the
  /// screen is a control nobody connects to the thing it changes.
  Widget _askMode() {
    if (!searched || error != null || results.isEmpty) {
      return const SizedBox.shrink();
    }

    Widget option({
      required bool selected,
      required IconData icon,
      required String title,
      required String note,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: PressableScale(
          onTap: onTap,
          child: AnimatedContainer(
            duration: Dur.quick,
            curve: Ease.standard,
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
            decoration: BoxDecoration(
              color: selected ? SC.blueTint : SC.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: selected ? SC.blueBright : SC.hairline,
                  width: selected ? 1.6 : 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(icon,
                        size: 17,
                        color: selected ? SC.blueBright : SC.inkFaint),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: selected ? SC.navy : SC.ink)),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(note, style: ST.small, maxLines: 2),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      // IntrinsicHeight, because the two cards should be the same height and
      // CrossAxisAlignment.stretch alone cannot do that here: a Row inside a
      // scroll view has no height of its own, so stretch hands its children
      // an infinite one and the layout throws. IntrinsicHeight measures the
      // taller card first and gives the Row that height to stretch into.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            option(
              selected: !askSeveral,
              icon: Icons.person_rounded,
              title: t('Ask one'),
              note: t('Tap a carer to read about them'),
              onTap: () => setState(() {
                askSeveral = false;
                chosen.clear();
              }),
            ),
            const SizedBox(width: 10),
            option(
              selected: askSeveral,
              icon: Icons.groups_rounded,
              title: t('Ask several'),
              note: t('Tap to tick. First to accept takes it'),
              onTap: () => setState(() => askSeveral = true),
            ),
          ],
        ),
      ),
    );
  }

  /// The bar that appears once carers have been ticked.
  ///
  /// Animated in rather than appearing, because it pushes the list up and a
  /// list that jumps under a finger mid-scroll is how you lose your place.
  Widget _askBar(BookingCriteria c) {
    final n = chosen.length;
    return AnimatedSize(
      duration: Dur.quick,
      curve: Ease.standard,
      child: n == 0
          ? const SizedBox(width: double.infinity)
          : Container(
              padding: EdgeInsets.fromLTRB(SC.gutter, 12, SC.gutter,
                  12 + MediaQuery.of(context).padding.bottom),
              decoration: const BoxDecoration(
                color: SC.surface,
                border: Border(top: BorderSide(color: SC.hairline)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                            n == 1
                                ? t('1 carer picked')
                                : t('{count} carers picked', {'count': n}),
                            style: ST.h3),
                        const SizedBox(height: 2),
                        // Short enough for two lines on a 375px phone beside
                        // both buttons. The longer version wrapped to three and
                        // pushed the bar over the card behind it.
                        Text(
                          n == 1
                              ? 'Only they will be asked'
                              : 'First to accept takes it',
                          style: ST.small,
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: () => setState(chosen.clear),
                    child: Text(t('Clear')),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 132,
                    child: GradientButton(
                      label: t('Ask them'),
                      icon: Icons.send_rounded,
                      height: 48,
                      onPressed: () => push(
                        context,
                        BookingConfirmScreen(
                            providerIds: chosen.toList(), criteria: c),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  /// The care type, as four cards. It is the choice everything else hangs off,
  /// so it is not hidden behind a dropdown.
  Widget _careTypes() {
    const icons = {
      ServiceType.companion: Icons.volunteer_activism_rounded,
      ServiceType.medicalCompanion: Icons.medical_information_rounded,
      ServiceType.nurse: Icons.medical_services_rounded,
      ServiceType.physiotherapy: Icons.accessibility_new_rounded,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(t('What kind of care')),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          // A nested scrollable inherits the ambient MediaQuery padding, which
          // here meant the grid reserved the phone-s bottom safe area and left
          // a dead band under the cards.
          padding: EdgeInsets.zero,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.5,
          // The loop variable is NOT called t: t() is the translation
          // function and shadowing it here silently turns every label in this
          // grid into a compile error at best and the wrong string at worst.
          children: ServiceType.values.map((svc) {
            final on = svc == type;
            // Nurse and Physiotherapy are shown but cannot be chosen: there
            // are no verified carers in either category yet, so a booking
            // would be taken and never filled. Greyed and labelled beats
            // hidden -- "not yet" is information, a missing card is not.
            final open = svc.bookable;
            return PressableScale(
              onTap: open
                  ? () => setState(() => type = svc)
                  : () => ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(t(
                              '{service} is not available yet. We will open it '
                              'as soon as verified carers have joined.',
                              {'service': svc.label})),
                        ),
                      ),
              child: AnimatedContainer(
                duration: Dur.quick,
                curve: Ease.standard,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: !open
                      ? SC.surfaceMuted
                      : on
                          ? SC.blueBright
                          : SC.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: !open
                          ? SC.hairlineCool
                          : on
                              ? SC.blueBright
                              : SC.hairline),
                  boxShadow: on && open ? SC.cardShadow : null,
                ),
                child: Row(
                  children: [
                    Icon(icons[svc],
                        size: 20,
                        color: !open
                            ? SC.inkFaint
                            : on
                                ? Colors.white
                                : SC.blueBright),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t(svc.label),
                            maxLines: 2,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                              color: !open
                                  ? SC.inkFaint
                                  : on
                                      ? Colors.white
                                      : SC.ink,
                            ),
                          ),
                          if (!open)
                            Text(t('Coming soon'),
                                style: const TextStyle(
                                    fontSize: 10.5,
                                    height: 1.3,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                    color: SC.inkFaint)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _whenAndWhere(BookingCriteria c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(t('When')),
        _row(
          icon: Icons.calendar_today_rounded,
          value: c.dateLabel,
          hint: c.days == 1 ? t('1 day') : t('{count} days', {'count': c.days}),
          onTap: _pickRange,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _row(
                icon: Icons.schedule_rounded,
                value: _fmt(timeFrom),
                hint: 'from',
                onTap: () => _pickTime(from: true),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _row(
                icon: Icons.schedule_rounded,
                value: _fmt(timeTo),
                hint: 'to',
                onTap: () => _pickTime(from: false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        FieldLabel(t('Where')),
        _row(
          icon: Icons.place_rounded,
          value: location == null ? 'No address saved' : location!.label,
          hint: location?.city ?? 'add one in your profile',
          onTap: _pickLocation,
        ),
        // The "Within N km" slider used to sit here. It was asking the
        // customer to solve the app's problem: nobody arranging care for a
        // parent thinks in kilometres, and every value it offered other than
        // the widest one could only ever hide carers. The search still has a
        // radius -- it has to -- but it is a default now, and the one case
        // where it matters is handled where it shows up, in the empty state.
      ],
    );
  }

  Widget _preferences() {
    return Row(
      children: [
        Expanded(
          child: _dropdown(
            label: t('Gender'),
            value: gender,
            options: const ['Any', 'Male', 'Female'],
            onChanged: (v) => setState(() => gender = v),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _dropdown(
            label: t('Language'),
            value: language,
            // The same list the provider app offers a carer, so the two
            // cannot drift apart. "Any" is first because it is the default
            // and it is not a language.
            options: const ['Any', ...kLanguages],
            onChanged: (v) => setState(() => language = v),
          ),
        ),
      ],
    );
  }

  Widget _resultsHeader(BookingCriteria c) {
    if (!searched || error != null || results.isEmpty) {
      return const SizedBox.shrink();
    }
    return Row(
      children: [
        Expanded(
          child: Text(
            '${results.length} available · ${c.totalHours.toStringAsFixed(1)} hours total',
            style: ST.small,
          ),
        ),
        PressableScale(
          onTap: _pickSort,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              color: SC.surface,
              borderRadius: BorderRadius.circular(SC.rPill),
              border: Border.all(color: SC.hairline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(sort.icon, size: 15, color: SC.blueBright),
                const SizedBox(width: 7),
                Text(sort.label,
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: SC.ink)),
                const Icon(Icons.expand_more_rounded,
                    size: 17, color: SC.inkFaint),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickSort() async {
    final chosen = await showModalBottomSheet<SortBy>(
      context: context,
      backgroundColor: SC.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                  color: SC.hairlineCool,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(t('Sort by'), style: ST.h2),
              ),
            ),
            ...SortBy.values.map(
              (s) => ListTile(
                leading: Icon(s.icon,
                    color: s == sort ? SC.blueBright : SC.inkFaint),
                title: Text(s.label,
                    style: s == sort
                        ? ST.h3.copyWith(color: SC.blueBright)
                        : ST.bodyStrong),
                trailing: s == sort
                    ? const Icon(Icons.check_rounded, color: SC.blueBright)
                    : null,
                onTap: () => Navigator.pop(context, s),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (chosen != null) setState(() => sort = chosen);
  }

  Widget _results(BookingCriteria c) {
    if (loading && results.isEmpty) {
      return const KeyedSubtree(
          key: ValueKey('loading'), child: SkeletonList(count: 3));
    }
    if (error != null) {
      return KeyedSubtree(
        key: const ValueKey('error'),
        child: InlineError(message: error!, onRetry: runSearch),
      );
    }
    if (!searched) return const SizedBox.shrink();

    if (results.isEmpty) {
      return KeyedSubtree(
        key: const ValueKey('empty'),
        child: EmptyState(
          icon: Icons.person_search_rounded,
          title: t('Nobody free for those hours'),
          message: t(
              'No {service} is available on those dates near {place}. Searching a '
              'wider area, or a different time, usually finds somebody.',
              {
                'service': type.label.toLowerCase(),
                'place': location?.city ?? kDefaultCity,
              }),
          actionLabel: t('Search a wider area'),
          onAction: () {
            setState(() => radiusKm = 50);
            runSearch();
          },
        ),
      );
    }

    final list = _sorted;
    return Column(
      key: ValueKey('results-${list.length}-${sort.name}'),
      children: [
        for (var i = 0; i < list.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == list.length - 1 ? 0 : 12),
            child: FadeInUp(index: i, child: _providerCard(list[i], c)),
          ),
      ],
    );
  }

  Widget _providerCard(Provider p, BookingCriteria c) {
    final km = _km(p);
    final picked = chosen.contains(p.id);

    return AnimatedContainer(
      duration: Dur.quick,
      curve: Ease.standard,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SC.rCard),
        // A picked card gets a ring rather than a different fill: the list has
        // to stay readable as a list, and a row of filled cards reads as a
        // different screen.
        border: Border.all(
          color: picked ? SC.blueBright : Colors.transparent,
          width: 2,
        ),
      ),
      child: SCard(
        padding: EdgeInsets.zero,
        // What a tap does depends on the mode chosen above the list. In "ask
        // one" it opens the profile, as it always has. In "ask several" the
        // whole card is the tick -- picking four people should be four taps
        // anywhere on four cards, not four taps on four 26px circles. The
        // profile is still one tap away, on the footer row.
        onTap: askSeveral
            ? () => _toggle(p)
            : () => push(
                  context,
                  ProviderDetailScreen(providerId: p.id, criteria: c),
                ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The tick sits on the avatar rather than beside it. As its own
                  // column it cost about 54px of a 315px row, and the names — the
                  // one thing on the card you have to be able to read — started
                  // truncating to "Josep…". On the portrait it costs nothing, and
                  // "selected" belongs on the person anyway.
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      InitialsAvatar(
                        name: p.name,
                        size: 58,
                        image: avatarImage(p.photoUrl),
                        badge: p.approved ? Icons.verified_rounded : null,
                      ),
                      // Only in "ask several". In "ask one" it is a control for
                      // something the customer has said they are not doing, and
                      // it was being hit by accident.
                      if (askSeveral)
                        Positioned(
                            left: -7, top: -7, child: _pickTick(p, picked)),
                    ],
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(p.name,
                                  style: ST.h3,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            const SizedBox(width: 8),
                            StarRating(
                                value: p.ratingAvg,
                                size: 14,
                                count: p.ratingCount),
                          ],
                        ),
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final e in p.expertise.take(2))
                              SkillTag(e.label),
                            if (p.noFees)
                              StatusChip(t('Volunteer'),
                                  tone: ChipTone.good, dense: true),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.place_rounded,
                                size: 13, color: SC.inkFaint),
                            const SizedBox(width: 4),
                            Text(
                                t('{km} km away',
                                    {'km': km.toStringAsFixed(1)}),
                                style: ST.small),
                            const SizedBox(width: 12),
                            const Icon(Icons.translate_rounded,
                                size: 13, color: SC.inkFaint),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(p.languages.take(2).join(', '),
                                  style: ST.small,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
              decoration: const BoxDecoration(
                color: SC.sunkTint,
                border: Border(top: BorderSide(color: SC.hairline)),
              ),
              child: Row(
                children: [
                  if (p.noFees)
                    Expanded(
                      child: Text(t('Free — gives their time'),
                          style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: SC.green)),
                    )
                  else
                    Expanded(
                      child: Text.rich(TextSpan(children: [
                        TextSpan(
                          text: '₹${p.hourlyRate?.toStringAsFixed(0) ?? '—'}',
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: SC.ink),
                        ),
                        const TextSpan(text: '  per hour', style: ST.small),
                      ])),
                    ),
                  // Its own tap target, because in "ask several" the card body
                  // ticks rather than opens, and reading about somebody before
                  // adding them to a shortlist is exactly what you want to do.
                  PressableScale(
                    onTap: () => push(
                      context,
                      ProviderDetailScreen(providerId: p.id, criteria: c),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(t('View profile'),
                              style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: SC.blueLink)),
                          const Icon(Icons.chevron_right_rounded,
                              size: 19, color: SC.blueLink),
                        ],
                      ),
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

  /// The tick that puts somebody on the shortlist.
  ///
  /// Its own tap target, separate from the card underneath, and padded out to
  /// about 40px — the circle is 26px and the rest is invisible and forgiving,
  /// which matters on the one control an older user is most likely to be
  /// aiming at one-handed.
  ///
  /// The white ring is not decoration: this sits on top of an avatar whose
  /// colour is derived from the person's name, so without it the outline
  /// disappears against roughly one initial in six.
  Widget _pickTick(Provider p, bool picked) {
    return PressableScale(
      scale: 0.88,
      onTap: () => _toggle(p),
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: AnimatedContainer(
          duration: Dur.quick,
          curve: Ease.standard,
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: picked ? SC.blueBright : SC.surface,
            shape: BoxShape.circle,
            border: Border.all(
              color: picked ? Colors.white : SC.hairlineCool,
              width: 2,
            ),
            boxShadow: SC.cardShadow,
          ),
          child: AnimatedScale(
            scale: picked ? 1 : 0,
            duration: Dur.micro,
            curve: Ease.pop,
            child:
                const Icon(Icons.check_rounded, size: 17, color: Colors.white),
          ),
        ),
      ),
    );
  }

  // ---- small pieces ---------------------------------------------------

  Widget _row({
    required IconData icon,
    required String value,
    required String hint,
    required VoidCallback onTap,
  }) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: SC.surface,
          borderRadius: BorderRadius.circular(SC.rField),
          border: Border.all(color: SC.hairline),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: SC.blueBright),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: ST.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (hint.isNotEmpty)
                    Text(hint,
                        style: ST.small.copyWith(fontSize: 11.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const Icon(Icons.unfold_more_rounded, size: 17, color: SC.inkFaint),
          ],
        ),
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: SC.surface,
            borderRadius: BorderRadius.circular(SC.rField),
            border: Border.all(color: SC.hairline),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              borderRadius: BorderRadius.circular(12),
              style: ST.bodyStrong,
              icon: const Icon(Icons.expand_more_rounded, color: SC.inkFaint),
              items: options
                  .map((o) => DropdownMenuItem(value: o, child: Text(t(o))))
                  .toList(),
              onChanged: (v) => onChanged(v!),
            ),
          ),
        ),
      ],
    );
  }
}
