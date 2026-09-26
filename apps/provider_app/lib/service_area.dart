// Where Sathiyaa actually works, and what happens to everybody else.
//
// Sathiyaa launches in Ahmedabad. Until now nothing in either app said so:
// somebody in Rajkot could register, search, find nobody, and reasonably
// conclude the app was broken. And the fact that they had tried was lost --
// which is the single most useful number a business opening one city at a
// time can have.
//
// So: register first, then check. Registering first is deliberate. Turning
// somebody away at the welcome screen tells us nothing; turning them away
// after they have given a name and a number leaves a row in the database
// saying a real person in Rajkot wanted this.
//
// THE DECISION IS THE SERVER'S. The app reports where the phone is; the
// server says whether that is inside. Two reasons. The obvious one is that an
// app which scores itself can be edited into saying yes. The one that matters
// more day to day is that the city, the centre and the radius live in
// app_configuration -- so opening Surat is a number typed into the admin
// console, not a new APK waiting three days in Play Store review.
//
// AND IT FAILS OPEN. If the phone refuses location, or the fix times out, or
// the network is down, the person gets into the app. Somebody outside the
// area who gets in sees a search with nobody in it -- mildly disappointing.
// Somebody inside the area who is locked out because they dismissed a
// permission dialog is gone for good and never tells you why. Those are not
// the same mistake, and this errs towards the cheap one.
//
// Shared by both apps and copied by _builds/sync-design.ps1. Nothing in here
// may reference Backend: the caller injects what it needs.

import 'package:flutter/material.dart';

import 'services/geocode.dart';
import 'services/location_service.dart';
import 'theme/sathiyaa_theme.dart';
import 'widgets/sathiyaa_ui.dart';
import 'i18n/l10n.dart';

/// The city Sathiyaa serves, as the server has it.
class ServiceArea {
  final bool enabled;
  final String city;
  final String state;
  final double lat;
  final double lng;
  final double radiusKm;

  const ServiceArea({
    required this.enabled,
    required this.city,
    required this.state,
    required this.lat,
    required this.lng,
    required this.radiusKm,
  });

  /// Used before the server has answered, and if it never does. Kept in step
  /// with migration 015, which seeds the same six values.
  static const fallback = ServiceArea(
    enabled: true,
    city: 'Ahmedabad',
    state: 'Gujarat',
    lat: 23.0225,
    lng: 72.5714,
    radiusKm: 35,
  );

  factory ServiceArea.fromJson(Map<String, dynamic> m) {
    double num_(Object? v, double fallbackValue) =>
        v == null ? fallbackValue : (double.tryParse('$v') ?? fallbackValue);
    return ServiceArea(
      enabled: '${m['enabled']}' != 'false',
      city: '${m['city'] ?? fallback.city}',
      state: '${m['state'] ?? fallback.state}',
      lat: num_(m['latitude'], fallback.lat),
      lng: num_(m['longitude'], fallback.lng),
      radiusKm: num_(m['radiusKm'], fallback.radiusKm),
    );
  }
}

/// What the app reports about where somebody registered from.
class SignupPlace {
  final double? lat;
  final double? lng;
  final String? city;
  final String? state;
  final String? pincode;

  const SignupPlace({this.lat, this.lng, this.city, this.state, this.pincode});

  Map<String, dynamic> toJson() => {
        'latitude': lat,
        'longitude': lng,
        'city': city,
        'state': state,
        'pincode': pincode,
      };
}

/// Decides between the app and the "not here yet" page.
///
/// Sits between registration and the home shell. Four states, and only one of
/// them shows a spinner:
///
///   demo          straight through; the demo data is not in any real city
///   known true    straight through
///   known false   the waiting-list page
///   not known     ask the phone once, report it, then one of the above
class ServiceAreaGate extends StatefulWidget {
  const ServiceAreaGate({
    super.key,
    required this.child,
    required this.known,
    required this.report,
    required this.area,
    required this.bypass,
    required this.audience,
  });

  /// The app, once somebody is through.
  final Widget child;

  /// What the server already said about this account: true, false, or null
  /// for "never asked". Null covers everybody who registered before this
  /// shipped, as well as anybody who refused the prompt last time.
  final bool? known;

  /// Sends the place to the server and returns the server's verdict.
  final Future<bool> Function(SignupPlace place) report;

  /// Where Sathiyaa works. [ServiceArea.fallback] until the server answers.
  final ServiceArea area;

  /// True in demo mode, where there is no server and no real city.
  final bool bypass;

  /// 'customer' or 'provider' — only changes the wording on the page.
  final String audience;

  @override
  State<ServiceAreaGate> createState() => _ServiceAreaGateState();
}

class _ServiceAreaGateState extends State<ServiceAreaGate> {
  /// null while we are still finding out.
  bool? _inside;
  String? _note;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    if (widget.bypass) {
      _inside = true;
    } else if (widget.known != null) {
      _inside = widget.known;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  Future<void> _check() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _note = null;
    });

    final fix = await LocationService.current();
    if (!mounted) return;

    if (!fix.isOk) {
      // Fails open, and says why it is asking rather than simply letting them
      // in with no explanation — somebody who meant to allow it can try again
      // from the button.
      setState(() {
        _checking = false;
        _inside = true;
        _note = fix.error;
      });
      return;
    }

    final place = await Geocode.reverse(fix.lat!, fix.lng!);
    if (!mounted) return;

    bool verdict;
    try {
      verdict = await widget.report(SignupPlace(
        lat: fix.lat,
        lng: fix.lng,
        city: place?.city,
        state: place?.state,
        pincode: place?.pincode,
      ));
    } catch (_) {
      // The server could not be reached. Not a reason to lock anybody out.
      verdict = true;
    }
    if (!mounted) return;
    setState(() {
      _checking = false;
      _inside = verdict;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_inside == true) return widget.child;
    if (_inside == false) {
      return OutsideServiceAreaScreen(area: widget.area, audience: widget.audience);
    }
    return _Checking(note: _note);
  }
}

/// The half-second between registering and being let in.
class _Checking extends StatelessWidget {
  const _Checking({this.note});
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SC.paper,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SathiyaaLogo(size: 64, onPaper: true),
              const SizedBox(height: 24),
              const SizedBox(
                width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4)),
              const SizedBox(height: 20),
              Text(t('Checking whether Sathiyaa covers your area…'),
                  textAlign: TextAlign.center, style: ST.body),
              if (note != null) ...[
                const SizedBox(height: 12),
                Text(note!, textAlign: TextAlign.center, style: ST.small),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown to somebody who registered from a city Sathiyaa has not opened yet.
///
/// The one thing this page must not do is read as a rejection. They are on a
/// list, their interest is what decides where Sathiyaa goes next, and saying
/// so plainly is both true and the only thing worth saying.
class OutsideServiceAreaScreen extends StatelessWidget {
  const OutsideServiceAreaScreen({
    super.key,
    required this.area,
    required this.audience,
  });

  final ServiceArea area;
  final String audience;

  @override
  Widget build(BuildContext context) {
    final forCarers = audience == 'provider';

    return Scaffold(
      backgroundColor: SC.paper,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(SC.gutter, 34, SC.gutter, 40),
          children: [
            const Center(child: SathiyaaLogo(size: 76, onPaper: true)),
            const SizedBox(height: 30),
            Text(
              t('Sathiyaa is not in your city yet'),
              textAlign: TextAlign.center,
              style: ST.h1,
            ),
            const SizedBox(height: 14),
            Text(
              t('We have started in {city}, and we are only as good as the carers we can actually send. Opening a city means finding and checking people there first — so we would rather not be in yours than be in it badly.',
                  {'city': area.city}),
              textAlign: TextAlign.center,
              style: ST.body.copyWith(height: 1.55),
            ),
            const SizedBox(height: 26),
            SCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: SC.greenTint,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.check_rounded,
                            size: 20, color: Color(0xFF1F7A45)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(t('Your account is saved'), style: ST.h3),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    forCarers
                        ? t('Nothing you entered is lost, and you do not need to register again. When Sathiyaa opens where you are we will call you on the number you signed up with — carers are the first thing we look for in a new city, so you would hear from us before the families do.')
                        : t('Nothing you entered is lost, and you do not need to register again. When Sathiyaa opens where you are we will call you on the number you signed up with. Families asking from a city is how we decide which one to open next, so this counts for more than it looks like.'),
                    style: ST.small.copyWith(height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('Where we are now'), style: ST.h3),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.place_rounded, size: 18, color: SC.blueBright),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('${area.city}, ${area.state}', style: ST.bodyStrong),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    t('If you are in {city} and this page is wrong, your phone may have placed you somewhere else. Close the app and open it again with location switched on.',
                        {'city': area.city}),
                    style: ST.small.copyWith(height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
