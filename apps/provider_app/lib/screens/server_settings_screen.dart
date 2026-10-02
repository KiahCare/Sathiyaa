import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../backend.dart';
import '../services/device_info.dart';
import '../theme/sathiyaa_theme.dart';
import '../widgets/motion.dart';
import '../widgets/sathiyaa_ui.dart';
import 'auth_screens.dart';
import '../i18n/l10n.dart';

/// Chooses between the built-in demo data and a live Sathiyaa server.
///
/// Switching modes signs you out, because the two worlds hold completely
/// different accounts — the demo customer only exists in memory, and a real
/// account only exists on the server.
///
/// Rebuilt on the design system. The two modes were radio rows whose subtitles
/// were the only thing that explained them; they are cards now, because this is
/// the one setting in the app that changes what everything else means.
class ServerSettingsScreen extends StatefulWidget {
  const ServerSettingsScreen({super.key});

  @override
  State<ServerSettingsScreen> createState() => _ServerSettingsScreenState();
}

class _ServerSettingsScreenState extends State<ServerSettingsScreen> {
  late final urlCtrl = TextEditingController(text: Backend.baseUrl);
  late BackendMode mode = Backend.mode;
  bool testing = false;
  String? testResult;
  bool testOk = false;

  @override
  void dispose() {
    urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() {
      testing = true;
      testResult = null;
    });
    final url = Backend.normaliseForDisplay(urlCtrl.text);
    try {
      // The server's own health check, which needs no parameters and no
      // sign-in. Using a search endpoint here meant a perfectly healthy server
      // answered "service_type and date_from are required", which reads like a
      // failure when it is the opposite.
      final health = url.replaceAll(RegExp(r'/api/v\d+/?$'), '');
      await ApiClient(health).get('/health');
      if (!mounted) return;
      setState(() {
        testOk = true;
        testResult = 'Connected. The Sathiyaa server answered at $url.';
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        // A structured reply still proves we reached something; only a network
        // failure means the address is wrong or unreachable.
        testOk = e.status != 0;
        testResult = e.status == 0
            ? e.message
            : 'Reached $url, but it did not look like a Sathiyaa server (${e.message}).';
      });
    } finally {
      if (mounted) setState(() => testing = false);
    }
  }

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await Backend.configure(mode: mode, baseUrl: urlCtrl.text);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(mode == BackendMode.live
          ? 'Now using the live server. Please sign in with your real PIN.'
          : 'Back on the built-in demo data.'),
    ));
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (r) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final changed = mode != Backend.mode ||
        Backend.normaliseForDisplay(urlCtrl.text) !=
            Backend.normaliseForDisplay(Backend.baseUrl);

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
                        Text(t('Server'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(t('Where this app gets its data'),
                            style: const TextStyle(color: Colors.white70, fontSize: 13.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(SC.gutter, 18, SC.gutter, 30),
              children: staggered([
                _modeCard(
                  value: BackendMode.mock,
                  icon: Icons.science_rounded,
                  title: t('Built-in demo data'),
                  body: 'Works with no server and no internet. Everything is '
                      'already filled in, and nothing you do is saved anywhere.',
                  tone: SC.gold,
                ),
                const SizedBox(height: 11),
                _modeCard(
                  value: BackendMode.live,
                  icon: Icons.cloud_rounded,
                  title: t('Live Sathiyaa server'),
                  body: 'Your real account, real jobs, written to the database '
                      'and visible to Sathiyaa in the admin console.',
                  tone: SC.green,
                ),
                if (mode == BackendMode.live) ...[
                  const SizedBox(height: 24),
                  SectionLabel(t('Server address')),
                  SCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FieldLabel(t('Address')),
                        TextField(
                          controller: urlCtrl,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          onChanged: (_) => setState(() => testResult = null),
                          decoration: const InputDecoration(hintText: '192.168.1.12:4000'),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t('Your computer\'s network address and the API port. The phone must be on the same Wi-Fi.'),
                          style: ST.small.copyWith(fontSize: 12, height: 1.45),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                size: 15, color: SC.amber),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                t('"localhost" will not work from a phone — to a phone, that means the phone itself.'),
                                style: ST.small.copyWith(fontSize: 12, height: 1.45),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          icon: testing
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.wifi_tethering_rounded, size: 18),
                          label: Text(testing ? 'Testing…' : 'Test connection'),
                          onPressed: testing ? null : _test,
                          style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(46)),
                        ),
                        if (testResult != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: testOk ? SC.greenTint : const Color(0xFFFCE9EA),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  testOk
                                      ? Icons.check_circle_rounded
                                      : Icons.error_outline_rounded,
                                  size: 17,
                                  color: testOk ? const Color(0xFF1F7A45) : SC.redDeep,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    testResult!,
                                    style: ST.small.copyWith(
                                      fontSize: 12.5,
                                      height: 1.45,
                                      color: testOk
                                          ? const Color(0xFF1F7A45)
                                          : SC.redDeep,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 26),
                GradientButton(
                  label: changed ? 'Save and start again' : 'Nothing to change',
                  icon: changed ? Icons.save_rounded : Icons.check_rounded,
                  onPressed: changed ? _save : null,
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: SC.sunkTint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.logout_rounded, size: 16, color: SC.inkFaint),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          t('Changing this signs you out. Demo accounts and real accounts are separate worlds.'),
                          style: ST.small.copyWith(fontSize: 12, height: 1.45),
                        ),
                      ),
                    ],
                  ),
                ),

                // What this build is.
                //
                // On the Server screen because that is where somebody already
                // is when they are being helped over the phone, and the first
                // question is always which version they are on. DeviceInfo has
                // read both of these since the device registry was added -- it
                // sends them as headers on every request -- and until now
                // there was nowhere in either app to see them.
                const SizedBox(height: 18),
                SectionLabel(t('This app')),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 15, color: SC.inkFaint),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        [
                          if (DeviceInfo.appVersion.isNotEmpty)
                            t('Version {v}', {'v': DeviceInfo.appVersion}),
                          DeviceInfo.summary,
                        ].join(' · '),
                        style: ST.small.copyWith(fontSize: 12, height: 1.45),
                      ),
                    ),
                  ],
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeCard({
    required BackendMode value,
    required IconData icon,
    required String title,
    required String body,
    required Color tone,
  }) {
    final on = mode == value;
    return PressableScale(
      onTap: () => setState(() => mode = value),
      child: AnimatedContainer(
        duration: Dur.quick,
        curve: Ease.enter,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: on ? SC.surface : SC.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(SC.rCard),
          border: Border.all(
            color: on ? tone : SC.hairline,
            width: on ? 1.9 : 1.2,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: on ? 0.16 : 0.08),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, size: 20, color: tone),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: ST.h3),
                  const SizedBox(height: 5),
                  Text(body, style: ST.small.copyWith(height: 1.45)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AnimatedContainer(
              duration: Dur.quick,
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? tone : Colors.transparent,
                border: Border.all(color: on ? tone : SC.hairlineCool, width: 1.8),
              ),
              child: on
                  ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Which backend the app is pointed at, shown on the Welcome screen.
///
/// It sits inside a translucent capsule on the dark header, so it brings no
/// background of its own — a light-grey pill inside a glass capsule looked like
/// two controls stacked by accident.
class BackendModeChip extends StatelessWidget {
  const BackendModeChip({super.key});

  @override
  Widget build(BuildContext context) {
    final live = Backend.isLive;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: live ? const Color(0xFF7BE0A6) : SC.gold,
          ),
        ),
        const SizedBox(width: 7),
        Text(
          live ? 'Live server' : 'Demo data',
          style: const TextStyle(
              fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white),
        ),
      ],
    );
  }
}
