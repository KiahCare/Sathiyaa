import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/sathiyaa_theme.dart';
import 'motion.dart';
import '../i18n/l10n.dart';

/// Picking one supporting document during registration.
///
/// Two rewrites' worth of history, because both mattered:
///
/// The first version offered a tick-box per document. Ticking it set a flag and
/// invented the filename "uploaded.jpg" — nothing was chosen and nothing was
/// sent, so an admin reviewing the application saw a row claiming a police
/// verification existed with no way to look at it.
///
/// The second picked a real file but was the only part of the app not built on
/// the design system: Material greys against warm paper, and a row holding a
/// thumbnail, a two-line label and a button, which on a 375px phone left the
/// button about forty pixels of room. It worked and looked broken, which is
/// indistinguishable from broken to the person using it.
///
/// This one is a card the size of the thing it is asking for. The whole card is
/// the target — there is no small button to miss — and the states are distinct
/// enough to read at a glance: nothing yet, chosen, or something went wrong.
///
/// The file is *sent* once the account exists, not here: the upload endpoint
/// needs a signed-in caller and during registration there is no account yet,
/// so uploading here would fail with a 401 on the one screen where that is
/// hardest to explain. ApiBackend.completeRegistration does it immediately
/// after the token arrives.
class DocumentField extends StatefulWidget {
  final String label;

  /// What this document is, for the upload endpoint and for the sheet's title.
  final String category;
  final bool required;

  /// A local file path once something is chosen. Null means nothing yet.
  final String? url;
  final ValueChanged<String?> onChanged;
  final String? errorText;

  /// One line saying what this document is for. Worth the space: half of these
  /// are refused because somebody photographed the wrong piece of paper.
  final String? hint;

  const DocumentField({
    super.key,
    required this.label,
    required this.category,
    required this.onChanged,
    this.required = false,
    this.url,
    this.errorText,
    this.hint,
  });

  @override
  State<DocumentField> createState() => _DocumentFieldState();
}

class _DocumentFieldState extends State<DocumentField> {
  bool _busy = false;
  String? _failure;

  bool get _has => widget.url != null && widget.url!.isNotEmpty;

  Future<void> _pick(ImageSource source) async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      // image_picker raises the platform's own permission prompt. On Android
      // 13+ the photo picker needs no storage permission at all, and on the web
      // it becomes an ordinary file input.
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2000,
        imageQuality: 85,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      // Cancelling is not a failure and must not leave an error on screen.
      if (picked == null) return;
      widget.onChanged(picked.path);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        // The raw exception here is usually a platform message nobody can act
        // on. Say what to do instead, and keep the detail for the second line.
        _failure = 'Could not open the picker. Check that Sathiyaa is allowed '
            'photos and camera in your phone settings.\n'
            '${e.toString().replaceFirst('Exception: ', '')}';
      });
    }
  }

  Future<void> _choose() async {
    final action = await showModalBottomSheet<_DocAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SourceSheet(title: widget.label, has: _has),
    );
    switch (action) {
      case null:
        return;
      case _DocAction.remove:
        widget.onChanged(null);
        setState(() => _failure = null);
      case _DocAction.camera:
        await _pick(ImageSource.camera);
      case _DocAction.gallery:
        await _pick(ImageSource.gallery);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.errorText ?? _failure;
    final bad = error != null;

    final borderColour = bad
        ? SC.red
        : _has
            ? SC.green
            : SC.hairline;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PressableScale(
            onTap: _busy ? null : _choose,
            child: AnimatedContainer(
              duration: Dur.quick,
              curve: Ease.standard,
              decoration: BoxDecoration(
                color: _has ? SC.greenTint : SC.surface,
                border: Border.all(color: borderColour, width: bad || _has ? 1.4 : 1),
                borderRadius: BorderRadius.circular(SC.rCard),
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _leading(bad),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    widget.label,
                                    style: ST.h2.copyWith(fontSize: 15),
                                  ),
                                ),
                                if (widget.required)
                                  const Text(' *',
                                      style: TextStyle(
                                          color: SC.red, fontWeight: FontWeight.w800)),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(_status(), style: ST.small.copyWith(
                              color: _has ? SC.green : SC.inkFaint,
                              fontWeight: _has ? FontWeight.w700 : FontWeight.w500,
                            )),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _trailing(),
                    ],
                  ),
                  if (widget.hint != null && !_has) ...[
                    const SizedBox(height: 10),
                    Text(widget.hint!, style: ST.small),
                  ],
                ],
              ),
            ),
          ),
          if (bad)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: Text(error,
                  style: ST.small.copyWith(color: SC.red, height: 1.35)),
            ),
        ],
      ),
    );
  }

  String _status() {
    if (_busy) return t('Opening…');
    if (_has) return t('Chosen — sent when you finish registering');
    return t('Tap to photograph it or pick a file');
  }

  Widget _leading(bool bad) {
    if (_has) return _preview(widget.url!);
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: bad ? SC.surface : SC.sunkTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        bad ? Icons.error_outline_rounded : Icons.description_outlined,
        color: bad ? SC.red : SC.inkFaint,
        size: 24,
      ),
    );
  }

  Widget _trailing() {
    if (_busy) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: SC.blueBright),
      );
    }
    // No small button to aim at: the whole card is the target, and this only
    // says which way it goes.
    return Icon(
      _has ? Icons.more_horiz_rounded : Icons.add_a_photo_outlined,
      color: _has ? SC.green : SC.blueBright,
      size: 22,
    );
  }

  Widget _preview(String path) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 48,
        height: 48,
        // dart:io has no File on the web, but image_picker hands back a blob:
        // URL there, which Image.network loads happily — so the web gets a real
        // preview too rather than a stand-in tick.
        child: kIsWeb
            ? Image.network(path, fit: BoxFit.cover, errorBuilder: _fallback)
            : Image.file(File(path), fit: BoxFit.cover, errorBuilder: _fallback),
      ),
    );
  }

  static Widget _fallback(BuildContext _, Object __, StackTrace? ___) => Container(
        color: SC.greenTint,
        child: const Icon(Icons.check_circle_rounded, color: SC.green, size: 26),
      );
}

/// What the sheet came back with. An enum of its own rather than an
/// [ImageSource], because "remove it" is not a source and squeezing it into one
/// is how a sentinel value ends up opening the camera.
enum _DocAction { camera, gallery, remove }

class _SourceSheet extends StatelessWidget {
  const _SourceSheet({required this.title, required this.has});

  final String title;
  final bool has;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: SC.surface,
          borderRadius: BorderRadius.circular(SC.rCard),
          border: Border.all(color: SC.hairline),
          boxShadow: SC.liftShadow,
        ),
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: SC.hairlineCool,
                borderRadius: BorderRadius.circular(SC.rPill),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(title, style: ST.h2, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 14),
            // The camera is how most of these will actually be captured;
            // offering only the gallery means photographing it in another app
            // first and coming back.
            if (!kIsWeb)
              _row(context, Icons.photo_camera_rounded, 'Take a photo',
                  'Point the camera at the document', _DocAction.camera),
            _row(context, Icons.photo_library_rounded, 'Choose a file',
                'A photo or scan already on this device', _DocAction.gallery),
            if (has)
              _row(context, Icons.delete_outline_rounded, 'Remove it',
                  'Take this document off the application', _DocAction.remove,
                  danger: true),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('Cancel')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String title, String sub,
      _DocAction value,
      {bool danger = false}) {
    final tint = danger ? SC.red : SC.blueBright;
    return PressableScale(
      onTap: () => Navigator.pop(context, value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: danger ? SC.surfaceMuted : SC.blueTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: tint, size: 21),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: ST.body.copyWith(
                          fontWeight: FontWeight.w700,
                          color: danger ? SC.red : SC.ink)),
                  Text(sub, style: ST.small),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
