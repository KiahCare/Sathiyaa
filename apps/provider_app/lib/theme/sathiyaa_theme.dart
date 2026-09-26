// Sathiyaa design system.
//
// Structure lives here; colour lives in palette.dart, which is the one file
// the two apps do NOT share. This file is authored in customer_app and copied
// into provider_app by _builds/sync-design.ps1 -- so spacing, radii, the type
// scale and every shadow stay identical, while each app keeps its own spine
// and its own paper.
//
// That split exists because the two apps are opened for different reasons. The
// customer app is a family at a worrying moment: warm cream, navy-to-blue,
// soft. The provider app is a carer between visits checking whether they are
// on duty: cool stone, teal, closer to an instrument. Same product, same
// shapes, different room.
//
// Constant across both: a gradient does the heavy lifting at the top of a
// screen, everything below sits on paper, cards are near-white with a hairline
// border and a very soft shadow, and exactly one thing on a screen is allowed
// to be red.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'palette.dart';

class SC {
  SC._();

  // ---- the blue spine -------------------------------------------------
  /// Gradient start. Also the colour of headings on cream.
  static const navy = P.navy;
  static const navyDeep = P.navyDeep;
  static const blue = P.blue;

  /// Gradient end, and the fill of a primary button.
  static const blueBright = P.blueBright;

  /// Links and the active tab in the bottom bar.
  static const blueLink = P.blueLink;
  static const blueTint = P.blueTint;

  // ---- paper ----------------------------------------------------------
  /// The page. Warm, not grey — this is most of what makes the reference
  /// look unlike a default Material app.
  static const paper = P.paper;
  static const paperWarm = P.paperWarm;

  /// A card sitting on [paper].
  static const surface = P.surface;
  static const white = P.white;

  /// A card that is deliberately quieter than its neighbours.
  static const surfaceMuted = P.surfaceMuted;
  static const hairline = P.hairline;
  /// The quiet fill behind an unselected icon tile.
  static const sunkTint = P.sunkTint;
  static const hairlineCool = P.hairlineCool;

  // ---- ink ------------------------------------------------------------
  static const ink = P.ink;
  static const inkSoft = P.inkSoft;
  static const inkFaint = P.inkFaint;

  // ---- accents --------------------------------------------------------
  /// Reserved for SOS and destructive confirmation. Nothing else.
  static const red = P.red;
  static const redDeep = P.redDeep;
  static const maroon = P.maroon;

  /// Badges, stars, the "Namaste" eyebrow, the counter on a filter chip.
  static const gold = P.gold;
  static const goldTint = P.goldTint;

  static const green = P.green;
  static const greenTint = P.greenTint;
  static const amber = P.amber;
  static const amberTint = P.amberTint;

  /// The bright mint from the brand mark. Legible only on the dark spine, so
  /// it is for eyebrows and highlights inside a gradient block -- never for
  /// text on paper, where it disappears.
  static const accentMint = P.accentMint;

  /// The one gradient. Used on the app header, primary buttons and the
  /// darker summary cards, always on this diagonal.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [navy, blueBright],
  );

  static const LinearGradient brandGradientDeep = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [navyDeep, blue],
  );

  static const LinearGradient sosGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFFCE2C36), red],
  );

  // ---- elevation ------------------------------------------------------
  // Warm-tinted rather than neutral black, so shadows sit on cream without
  // going grey.
  static List<BoxShadow> get cardShadow => const [
        BoxShadow(color: Color(0x0F4A3B2A), blurRadius: 14, offset: Offset(0, 4)),
      ];

  static List<BoxShadow> get liftShadow => const [
        BoxShadow(color: Color(0x1A2A3B4A), blurRadius: 24, offset: Offset(0, 8)),
      ];

  // ---- geometry -------------------------------------------------------
  static const rCard = 18.0;
  static const rField = 14.0;
  static const rPill = 999.0;
  static const gutter = 18.0;
}

/// Type scale. One family, used at six sizes — the reference leans on weight
/// and colour for hierarchy rather than on many faces.
class ST {
  ST._();

  static const _f = 'Inter';

  static const display = TextStyle(
    fontFamily: _f,
    fontSize: 30,
    fontWeight: FontWeight.w800,
    height: 1.12,
    letterSpacing: -0.6,
    fontStyle: FontStyle.italic,
    color: Colors.white,
  );

  static const h1 = TextStyle(
    fontFamily: _f,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.3,
    color: SC.ink,
  );

  static const h2 = TextStyle(
    fontFamily: _f,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: -0.2,
    color: SC.ink,
  );

  static const h3 = TextStyle(
    fontFamily: _f,
    fontSize: 15.5,
    fontWeight: FontWeight.w700,
    height: 1.3,
    color: SC.ink,
  );

  static const body = TextStyle(
    fontFamily: _f,
    fontSize: 14.5,
    fontWeight: FontWeight.w400,
    height: 1.45,
    color: SC.inkSoft,
  );

  static const bodyStrong = TextStyle(
    fontFamily: _f,
    fontSize: 14.5,
    fontWeight: FontWeight.w600,
    height: 1.4,
    color: SC.ink,
  );

  static const small = TextStyle(
    fontFamily: _f,
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    height: 1.35,
    color: SC.inkFaint,
  );

  /// Uppercase field labels and eyebrows — SERVICE DATES, CARE TYPE.
  static const label = TextStyle(
    fontFamily: _f,
    fontSize: 11.5,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 0.9,
    color: SC.inkFaint,
  );

  /// A number that is the point of its tile — ₹19,470, 10.5, 02:45:12.
  static const figure = TextStyle(
    fontFamily: _f,
    fontSize: 27,
    fontWeight: FontWeight.w800,
    height: 1.05,
    letterSpacing: -0.5,
    color: SC.ink,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

ThemeData buildSathiyaaTheme() {
  const scheme = ColorScheme.light(
    primary: SC.blueBright,
    onPrimary: Colors.white,
    secondary: SC.gold,
    onSecondary: Colors.white,
    surface: SC.surface,
    onSurface: SC.ink,
    error: SC.red,
    onError: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: SC.paper,
    fontFamily: 'Inter',
    splashFactory: InkSparkle.splashFactory,

    appBarTheme: const AppBarTheme(
      backgroundColor: SC.paper,
      surfaceTintColor: Colors.transparent,
      foregroundColor: SC.ink,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: ST.h1,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: SC.blueBright,
        foregroundColor: Colors.white,
        disabledBackgroundColor: SC.hairlineCool,
        disabledForegroundColor: SC.inkFaint,
        elevation: 0,
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SC.rField)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.1),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: SC.navy,
        minimumSize: const Size.fromHeight(50),
        side: const BorderSide(color: SC.hairline, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SC.rField)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: SC.blueLink,
        textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SC.surface,
      hintStyle: ST.body.copyWith(color: SC.inkFaint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SC.rField),
        borderSide: const BorderSide(color: SC.hairline, width: 1.2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SC.rField),
        borderSide: const BorderSide(color: SC.hairline, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SC.rField),
        borderSide: const BorderSide(color: SC.blueBright, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SC.rField),
        borderSide: const BorderSide(color: SC.red, width: 1.6),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SC.rField),
        borderSide: const BorderSide(color: SC.red, width: 1.8),
      ),
      errorStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: SC.red),
    ),

    cardTheme: CardThemeData(
      color: SC.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SC.rCard),
        side: const BorderSide(color: SC.hairline),
      ),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: SC.surface,
      side: const BorderSide(color: SC.hairline),
      labelStyle: ST.bodyStrong.copyWith(fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SC.rPill)),
    ),

    dividerTheme: const DividerThemeData(color: SC.hairline, thickness: 1, space: 1),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: SC.navy,
      contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),

    textTheme: const TextTheme(
      headlineLarge: ST.h1,
      titleLarge: ST.h2,
      titleMedium: ST.h3,
      bodyLarge: ST.bodyStrong,
      bodyMedium: ST.body,
      bodySmall: ST.small,
      labelSmall: ST.label,
    ),
  );
}
