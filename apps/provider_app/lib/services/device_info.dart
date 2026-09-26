import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../i18n/l10n.dart';

/// What this handset is, as headers the API records against the account.
///
/// Read once at startup and cached: the make and model of a phone do not
/// change while the app is open, and asking the platform channel on every
/// request would be work for nothing.
///
/// What is collected is what the handset tells any installed app about itself
/// — manufacturer, model, OS version — plus the app's own version. Nothing
/// that follows a person between apps: no advertising id, no IMEI. Android
/// stopped handing that out at version 10, and it was the wrong thing to
/// collect before that.
///
/// Every field is optional. A platform that will not answer, or a plugin that
/// throws on a device nobody anticipated, leaves the header out rather than
/// stopping the app from starting.
class DeviceInfo {
  DeviceInfo._();

  static Map<String, String> _headers = const {};

  /// The headers to attach to every request. Empty until [load] has run.
  static Map<String, String> get headers => _headers;

  /// A short line for the Server screen, so somebody can read out what they
  /// are on without digging through settings.
  static String get summary {
    final model = _headers['X-Device-Model'];
    final os = _headers['X-Device-OS'];
    if (model == null && os == null) return t('Unknown device');
    return [model, os].where((s) => s != null && s.isNotEmpty).join(' · ');
  }

  static Future<void> load() async {
    final out = <String, String>{};

    try {
      final pkg = await PackageInfo.fromPlatform();
      final v = pkg.version.isEmpty ? null : pkg.version;
      final b = pkg.buildNumber.isEmpty ? null : pkg.buildNumber;
      if (v != null) out['X-App-Version'] = b == null ? v : '$v+$b';
    } catch (_) {
      // No package metadata on some desktop and test hosts. Not worth a line
      // in the log, and certainly not worth failing startup for.
    }

    try {
      final plugin = DeviceInfoPlugin();

      if (kIsWeb) {
        final web = await plugin.webBrowserInfo;
        out['X-Device-Platform'] = 'web';
        final browser = web.browserName.name;
        if (browser.isNotEmpty) out['X-Device-Model'] = browser;
        final platform = web.platform;
        if (platform != null && platform.isNotEmpty) out['X-Device-OS'] = platform;
        out['X-Device-Physical'] = 'true';
      } else {
        switch (defaultTargetPlatform) {
          case TargetPlatform.android:
            final a = await plugin.androidInfo;
            out['X-Device-Platform'] = 'android';
            out['X-Device-Manufacturer'] = a.manufacturer;
            out['X-Device-Model'] = a.model;
            // Both numbers, because they answer different questions: "Android
            // 13" is what the owner calls it, SDK 33 is what a support person
            // needs to know which behaviour applies.
            out['X-Device-OS'] = 'Android ${a.version.release} (SDK ${a.version.sdkInt})';
            out['X-Device-Physical'] = a.isPhysicalDevice.toString();
            break;

          case TargetPlatform.iOS:
            final i = await plugin.iosInfo;
            out['X-Device-Platform'] = 'ios';
            out['X-Device-Manufacturer'] = 'Apple';
            // utsname.machine is the hardware identifier — iPhone14,5 — which
            // is the one that pins down the actual handset. `model` only ever
            // says "iPhone".
            out['X-Device-Model'] = i.utsname.machine;
            out['X-Device-OS'] = 'iOS ${i.systemVersion}';
            out['X-Device-Physical'] = i.isPhysicalDevice.toString();
            break;

          default:
            out['X-Device-Platform'] = defaultTargetPlatform.name;
        }
      }
    } catch (e) {
      // A plugin that throws on some handset nobody has seen must not be the
      // reason the app will not open.
      debugPrint('[device] could not read device details: $e');
    }

    out.removeWhere((_, v) => v.isEmpty);
    _headers = Map.unmodifiable(out);
  }
}
