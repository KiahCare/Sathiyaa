// The provider app's colours.
//
// This is the one file in the design system that is deliberately NOT shared.
// Everything else -- spacing, radii, type scale, shadows, every widget in
// sathiyaa_ui.dart -- is authored in customer_app and copied here by
// _builds/sync-design.ps1, so the two apps stay one product. The palette is
// excluded from that copy, which is what lets them look like two apps.
//
// Why these values
// ----------------
// The customer app now carries the website's teal, because a family that has
// read sathiyaa.in and then opens the app should land somewhere familiar.
// That freed the navy-and-blue this app used to share with it, and navy is
// the better fit here anyway.
//
// A carer opens this between visits, often outdoors, to see whether they are
// on duty, what is next, and whether they have been paid. Navy on cream is
// the higher-contrast pair in daylight, and it is now unmistakably NOT the
// customer app -- which matters, because many people will have both installed
// and will be glancing at a home screen, not reading labels.
//
// What deliberately did NOT change:
//   - red     still the only alarm colour, still nothing else
//   - gold    ratings and badges, shared with the customer app so a star
//             means the same thing in both
//   - green   success, at the customer app's old value, which was tuned
//             against exactly this navy
//
// Keep the NAMES identical to customer_app/lib/theme/palette.dart. The shared
// theme file aliases every one of them, so a name that exists in one palette
// and not the other stops the other app compiling -- and sync-design.ps1
// refuses to run when the two disagree.

import 'package:flutter/material.dart';

class P {
  P._();

  // ---- the spine: navy to blue ----------------------------------------
  /// Gradient start, and the colour of headings on paper.
  static const navy = Color(0xFF0D3147);
  static const navyDeep = Color(0xFF0A2334);
  static const blue = Color(0xFF145887);

  /// Gradient end, and the fill of a primary button.
  static const blueBright = Color(0xFF1B6DA5);

  /// Links. A step brighter than the spine, so it still reads as a link.
  static const blueLink = Color(0xFF0E6CC4);
  static const blueTint = Color(0xFFEAF4FE);

  // ---- paper: warm cream ----------------------------------------------
  static const paper = Color(0xFFFDF8F2);
  static const paperWarm = Color(0xFFFBF2ED);
  static const surface = Color(0xFFFFFCF5);
  static const white = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFEFEEEC);
  static const hairline = Color(0xFFF0ECE0);
  static const sunkTint = Color(0xFFF2F4F6);
  static const hairlineCool = Color(0xFFE4E7EA);

  // ---- ink -------------------------------------------------------------
  static const ink = Color(0xFF12222E);
  static const inkSoft = Color(0xFF5A6B77);
  static const inkFaint = Color(0xFF8A99A3);

  // ---- accents ---------------------------------------------------------
  /// Reserved for the emergency path. Nothing else is allowed to be red.
  static const red = Color(0xFFE33944);
  static const redDeep = Color(0xFFD71617);
  static const maroon = Color(0xFF5B1700);

  static const gold = Color(0xFFC9922E);
  static const goldTint = Color(0xFFFBF1DC);

  static const green = Color(0xFF2E9E5B);
  static const greenTint = Color(0xFFE6F4EC);
  static const amber = Color(0xFFE8912B);
  static const amberTint = Color(0xFFFDF0DC);

  /// The bright mint from the brand mark. Used sparingly, on navy only.
  static const accentMint = Color(0xFF72E6DF);
}
