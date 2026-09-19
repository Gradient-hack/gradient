import 'package:flutter/material.dart';

/// Gradient brand palette, built from the FlashForce colours: its green
/// brand hue, near-black CTAs and cool greys, plus the mint / coral / amber
/// accents FlashForce uses for checks, errors and ratings.
class AppColors {
  const AppColors._();

  /// Brand green (FlashForce `GreenAppButtonColor`) — the Material primary.
  static const primary = Color(0xFF39AD34);

  /// Deeper green (FlashForce success green) — gradient start, host A.
  static const primaryDark = Color(0xFF1B8A3F);

  /// Mint (FlashForce check colour) — success, correct answers, arrival.
  static const mint = Color(0xFF3DDCB4);

  /// Coral (FlashForce error tone) — warm accent, wrong answers, host B.
  static const accent = Color(0xFFFF6B6B);

  /// Amber (FlashForce rating stars) — photos, keepsakes, highlights.
  static const amber = Color(0xFFFFB800);

  /// Near-black (FlashForce filled buttons and headings).
  static const ink = Color(0xFF111111);

  static const background = Color(0xFFF4F4F4);
  static const surface = Colors.white;
  static const surfaceMuted = Color(0xFFF5F5F7);
  static const gray = Color(0xFF6E6E7A);
  static const hint = Color(0xFFAEAEB2);
  static const border = Color(0xFFE4E4EB);
  static const borderStrong = Color(0xFFCFCFD6);
  static const text = ink;
  static const error = Color(0xFFE53935);

  /// Voice colours for the two podcast hosts.
  static const hostA = primaryDark;
  static const hostB = accent;

  /// Accent hues cycled over tag-like things (interest chips).
  static const tags = [primary, mint, amber, accent, primaryDark];

  /// The signature brand gradient (used for hero surfaces and CTAs).
  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryDark, primary, mint],
  );

  /// Softer variant for backgrounds behind text.
  static const softGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFEAF7E7), Color(0xFFE3FAF3)],
  );

  /// Warm variant for photo / keepsake surfaces.
  static const warmGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFF4D6), Color(0xFFFFE8E4)],
  );
}
