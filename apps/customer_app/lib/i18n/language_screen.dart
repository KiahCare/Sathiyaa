// The language picker.
//
// Each language is written in its own script -- हिन्दी, not "Hindi". Somebody
// who cannot read English cannot find their language in a list written in
// English, which is the one job this screen has.

import 'package:flutter/material.dart';

import '../theme/sathiyaa_theme.dart';
import '../widgets/sathiyaa_ui.dart';
import 'l10n.dart';

class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  /// Sets the language, then offers to restart.
  ///
  /// The offer is not a formality. Changing the language rebuilds the app, and
  /// that catches nearly everything -- but a screen that captured its labels
  /// in a `late final` or built them once in initState keeps the words it was
  /// born with, because a rebuild re-runs `build` and not `initState`. The
  /// shell holding the bottom navigation bar is one of those, and it is never
  /// disposed while the app is open.
  ///
  /// So: say plainly that a restart finishes the job, and let the person
  /// decline. Somebody halfway through filling in a form should not have it
  /// taken away because they corrected the language first.
  Future<void> _choose(AppLanguage lang) async {
    final already = Lang.current.value == lang;
    await Lang.set(lang);
    if (!mounted) return;
    setState(() {});
    if (already) return;

    final restart = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: SC.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SC.rCard)),
        title: Text(t('Restart the app?'), style: ST.h2),
        content: Text(
          t('Sathiyaa is now in {language}. Most of it has changed already — restarting makes sure every screen has.',
              {'language': lang.nativeName}),
          style: ST.body.copyWith(height: 1.5),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(t('Not now')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SC.blueBright),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(t('Restart now')),
          ),
        ],
      ),
    );

    if (restart != true || !mounted) return;
    // Back to the first screen before the tree is thrown away, so the restart
    // does not happen underneath a route that no longer exists.
    Navigator.of(context).popUntil((r) => r.isFirst);
    LanguageScope.restart(context);
  }

  @override
  Widget build(BuildContext context) {
    final selected = Lang.current.value;

    return Scaffold(
      backgroundColor: SC.paper,
      body: Column(
        children: [
          BrandHeader(
            curved: false,
            child: BrandBar(
              title: t('Language'),
              subtitle: t('Choose your language'),
              onBack: () => Navigator.of(context).maybePop(),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(SC.gutter, 18, SC.gutter, 24),
              children: [
                for (final lang in AppLanguage.values) ...[
                  _LanguageTile(
                    language: lang,
                    selected: lang == selected,
                    onTap: () => _choose(lang),
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 8),
                Text(
                  t('Sathiyaa uses this language everywhere in the app.'),
                  style: ST.small,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.language,
    required this.selected,
    required this.onTap,
  });

  final AppLanguage language;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SCard(
      onTap: onTap,
      border: selected ? SC.blueBright : null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The native name is the heading, at heading size. It is what
                // the person is looking for.
                Text(language.nativeName, style: ST.h2),
                if (language.nativeName != language.englishName)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(language.englishName, style: ST.small),
                  ),
              ],
            ),
          ),
          Icon(
            selected ? Icons.check_circle_rounded : Icons.circle_outlined,
            color: selected ? SC.blueBright : SC.inkFaint,
            size: 24,
          ),
        ],
      ),
    );
  }
}
