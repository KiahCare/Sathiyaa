// The customer app's colours.
//
// This is the one file in the design system that is deliberately NOT shared.
// Everything else -- spacing, radii, type scale, shadows, every widget in
// sathiyaa_ui.dart -- is authored here and copied into provider_app by
// _builds/sync-design.ps1, so the two apps stay one product. The palette is
// excluded from that copy, which is what lets them look like two apps.
//
// Where these values come from
// ----------------------------
// sathiyaa.in. Not "a teal that looks about right" -- the site's own CSS
// custom properties, read off the live page:
//
//     --blue2  #064A4C     --blue  #096F73     --teal  #72E6DF
//     --mint   #137F82     --muted #C8E8E7     --ink   #F4FFFF
//
// A family that has read the website and then opens the app should not have
// to wonder whether they are in the right place, so the spine is the site's
// spine and the hero gradient is the site's hero gradient.
//
// Keep the NAMES identical to provider_app/lib/theme/palette.dart. The shared
// theme file aliases every one of them, so a name that exists in one palette
// and not the other stops the other app compiling -- and sync-design.ps1
// refuses to run when the two disagree.

import 'package:flutter/material.dart';

class P {
  P._();

  // ---- the spine: the website's teal -----------------------------------
  /// Gradient start, and the colour of headings on paper.
  static const navy = Color(0xFF064A4C);
  static const navyDeep = Color(0xFF043336);

  /// The brand itself: --blue on sathiyaa.in.
  static const blue = Color(0xFF096F73);

  /// Gradient end, and the fill of a primary button. The site's hero runs
  /// #0F8588 -> #096F73; this is that lighter end.
  static const blueBright = Color(0xFF12868A);

  /// Links. Blue, because the spine is not -- a teal link on a teal-headed
  /// screen reads as decoration rather than as something to tap.
  static const blueLink = Color(0xFF0E6CC4);
  static const blueTint = Color(0xFFE2F4F3);

  // ---- paper: pale mint, the site's light sections ---------------------
  static const paper = Color(0xFFF2FAF9);
  static const paperWarm = Color(0xFFE9F5F4);
  static const surface = Color(0xFFFFFFFF);
  static const white = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFEAF2F1);
  static const hairline = Color(0xFFDCEBE9);
  static const sunkTint = Color(0xFFEEF6F5);
  static const hairlineCool = Color(0xFFD6E6E4);

  // ---- ink -------------------------------------------------------------
  static const ink = Color(0xFF0C2321);
  static const inkSoft = Color(0xFF4F6461);
  static const inkFaint = Color(0xFF82938F);

  // ---- accents ---------------------------------------------------------
  /// Reserved for SOS. Nothing else on any screen is allowed to be red.
  static const red = Color(0xFFE33944);
  static const redDeep = Color(0xFFD71617);
  static const maroon = Color(0xFF5B1700);

  static const gold = Color(0xFFC9922E);
  static const goldTint = Color(0xFFFBF1DC);

  /// Bright enough to still read as "good" beside a teal brand, rather than
  /// as more of the brand.
  static const green = Color(0xFF1FA055);
  static const greenTint = Color(0xFFE4F5EA);
  static const amber = Color(0xFFE8912B);
  static const amberTint = Color(0xFFFDF0DC);

  /// The site's bright mint. Used sparingly, on dark teal only -- an eyebrow,
  /// a highlight inside the hero -- where it is the one thing that lifts.
  static const accentMint = Color(0xFF72E6DF);
}
