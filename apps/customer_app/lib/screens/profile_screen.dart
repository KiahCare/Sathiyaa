import 'package:flutter/material.dart';

import '../models.dart';
import '../backend.dart';
import '../widgets/common.dart';
import '../theme/sathiyaa_theme.dart';
import '../widgets/sathiyaa_ui.dart';
import '../widgets/motion.dart';
import 'account_sections.dart';
import 'basic_details_screen.dart';
import 'linked_providers_screen.dart';
import 'profile_sections.dart';
import '../i18n/l10n.dart';
import '../i18n/language_screen.dart';
import 'server_settings_screen.dart';
import 'splash_and_auth.dart';
import '../utils/dates.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  void _refresh() => setState(() {});

  Future<void> _confirmLogOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: SC.surface,
        title: Text(t('Log out?'), style: ST.h2),
        content: Text(
          t('You will need your mobile number and a new code to sign back in.'),
          style: ST.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('Stay signed in')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: SC.redDeep),
            child: Text(t('Log out')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final navigator = Navigator.of(context);
    await Backend.instance.signOut();
    if (!mounted) return;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (r) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = Backend.instance.currentCustomer!;
    final photoProvider = avatarImage(c.photoUrl);
    final hasPhoto = photoProvider != null;
    final primary = Backend.instance.primaryAddress();
    final incomplete = <String>[
      if (!hasPhoto) 'photo',
      if (c.dob == null) 'date of birth',
      if (c.gender == null) 'gender',
      if (primary == null || primary.line1.isEmpty) 'primary address',
    ];

    return Scaffold(
      backgroundColor: SC.paper,
      body: Column(
        children: [
          BrandHeader(
            curved: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, SC.gutter, 6),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.chevron_left_rounded,
                            color: Colors.white, size: 30),
                      ),
                      const Spacer(),
                      HeaderIconButton(
                        icon: Icons.translate_rounded,
                        tooltip: t('Language'),
                        onTap: () => push(context, const LanguageScreen()),
                      ),
                      const SizedBox(width: 8),
                      HeaderIconButton(
                        icon: Icons.dns_rounded,
                        tooltip: t('Server'),
                        onTap: () => push(context, const ServerSettingsScreen()),
                      ),
                      const SizedBox(width: 8),
                      // Beside language and server rather than at the bottom
                      // of a long scroll. Logging out is something people
                      // reach for deliberately and want to find, and it asks
                      // first because the account is tied to this handset --
                      // signing back in needs the OTP.
                      HeaderIconButton(
                        icon: Icons.logout_rounded,
                        tooltip: t('Log out'),
                        onTap: _confirmLogOut,
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 2, 0, 4),
                    child: Row(
                      children: [
                        InitialsAvatar(
                          name: c.name,
                          size: 66,
                          radius: 21,
                          image: photoProvider,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 21,
                                      fontWeight: FontWeight.w800,
                                      height: 1.15)),
                              const SizedBox(height: 4),
                              Text('${c.id}  ·  ${c.mobile}',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(SC.gutter, 18, SC.gutter, 32),
              children: [
          if (incomplete.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: SC.amberTint,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFF0DCBC)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 18, color: Color(0xFFA9670F)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Still needed: ${incomplete.join(', ')}. Open Basic details '
                        'to finish your profile.',
                        style: ST.small.copyWith(
                            color: const Color(0xFF8A5510), height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // --- Basic details (its own screen — it's a long form) ------------
          SectionCard(
            title: t('Basic details'),
            trailing: TextButton.icon(
              icon: const Icon(Icons.edit, size: 16),
              label: Text(t('Edit')),
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BasicDetailsScreen()));
                _refresh();
              },
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kv('Age', c.dob == null ? '—' : '${_age(c.dob!)} (${prettyDate(c.dob!)})'),
                _kv('Gender', c.gender ?? '—'),
                _kv('Blood group', c.bloodGroup ?? '—'),
                _kv('Email', c.email ?? '—'),
                _kv('Languages', c.preferredLanguages.isEmpty ? '—' : c.preferredLanguages.join(', ')),
                _kv(
                  'Height / Weight / BMI',
                  '${c.heightCm?.toStringAsFixed(0) ?? '—'} cm · ${c.weightKg?.toStringAsFixed(0) ?? '—'} kg · BMI ${c.bmi?.toStringAsFixed(1) ?? '—'}',
                ),
                _kv('Contact via', c.contactModes.isEmpty ? '—' : '${c.contactModes.map((m) => m.label).join(', ')}${c.contactTimeframe == null ? '' : ' (${c.contactTimeframe})'}'),
                const SizedBox(height: 8),
                for (final a in c.addresses)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('${a.label}: ${a.line1}, ${a.city}', style: const TextStyle(fontSize: 13)),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 22),
          RegistrationPaymentCard(onChanged: _refresh),
          const SizedBox(height: 22),
          ReferenceCodeCard(onChanged: _refresh),

          // --- The six expand/collapse health sections ----------------------
          const SizedBox(height: 22),
          SectionLabel(t('Health record')),
          ExpandableSection(
            title: t('Vitals'),
            icon: Icons.monitor_heart_rounded,
            badge: '${c.vitals.length}/5',
            children: [VitalsSection(onChanged: _refresh)],
          ),
          ExpandableSection(
            title: t('Medications'),
            icon: Icons.medication_rounded,
            badge: '${c.medications.length}/5',
            children: [MedicationsSection(onChanged: _refresh)],
          ),
          ExpandableSection(
            title: t('Surgeries'),
            icon: Icons.healing_rounded,
            badge: '${c.surgeries.length}/5',
            children: [SurgeriesSection(onChanged: _refresh)],
          ),
          ExpandableSection(
            title: t('Allergies'),
            icon: Icons.coronavirus_rounded,
            badge: '${c.allergies.length}/5',
            children: [AllergiesSection(onChanged: _refresh)],
          ),
          ExpandableSection(
            title: t('Insurance'),
            icon: Icons.shield_rounded,
            badge: '${c.insurance.length}',
            children: [InsuranceSection(onChanged: _refresh)],
          ),
          ExpandableSection(
            title: t('Family details'),
            icon: Icons.group_rounded,
            badge: '${c.family.where((f) => f.active).length}/5',
            children: [FamilySection(onChanged: _refresh)],
          ),

          const SizedBox(height: 12),
          SCard(
            padding: const EdgeInsets.all(14),
            onTap: () async {
              await push(context, const LinkedProvidersScreen());
              _refresh();
            },
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: SC.blueTint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.bookmark_rounded,
                      size: 19, color: SC.blueBright),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(t('My regular carers'), style: ST.h3)),
                StatusChip('${c.linkedProviderIds.length}/10',
                    tone: ChipTone.info, dense: true),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded, color: SC.inkFaint),
              ],
            ),
          ),

              ],
            ),
          ),
        ],
      ),
    );
  }

  static int _age(DateTime dob) {
    final now = DateTime.now();
    var age = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) age--;
    return age;
  }

  /// One label/value line.
  ///
  /// The label used to take a fixed 150px, which on a normal phone left under
  /// 180px for the value — long ones like "Height / Weight / BMI" and a full
  /// list of contact modes ran out of room and looked cramped against the
  /// label. Narrow screens now stack the value under its label instead.
  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: LayoutBuilder(
        builder: (context, box) {
          final label = Text(k, style: const TextStyle(color: Colors.black54, fontSize: 13));
          final value = Text(v, style: const TextStyle(fontSize: 13.5));
          if (box.maxWidth < 340) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [label, const SizedBox(height: 1), value],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 132, child: label),
              const SizedBox(width: 8),
              Expanded(child: value),
            ],
          );
        },
      ),
    );
  }
}
