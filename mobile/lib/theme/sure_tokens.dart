// GENERATED CODE - DO NOT EDIT BY HAND.
// Modified by Cardona Labs, LLC, 2026-11-03, AGPL-3.0
// Source: design/tokens/sure.tokens.json
// Build: node mobile/tool/generate_sure_tokens.mjs

import 'package:flutter/painting.dart';

class SureTokens {
  const SureTokens._();

  static const String version = '2.1.1';
  static const String fontSans = 'Space Grotesk Variable';
  static const String fontMono = 'JetBrains Mono Variable';

  // Keep the existing Flutter fallback behavior until native mobile font assets
  // are registered. The canonical web stack remains in sure.tokens.json.
  static const List<String> fontFallback = <String>[
    'Inter',
    'Arial',
    'sans-serif',
  ];

  static const double radiusMd = 8.0;
  static const double radiusLg = 10.0;

  static const FontWeight weightMedium = FontWeight.w500;
  static const FontWeight weightSemibold = FontWeight.w600;

  static const light = SureTokenPalette(
    surface: Color(0xFFF7F1E7),
    surfaceHover: Color(0xFFF1E9D9),
    surfaceInset: Color(0xFFF1E9D9),
    surfaceInsetHover: Color(0xFFE7DCC7),
    container: Color(0xFFFBF7F0),
    containerHover: Color(0xFFF7F1E7),
    containerInset: Color(0xFFF1E9D9),
    containerInsetHover: Color(0xFFE7DCC7),
    success: Color(0xFF078C52),
    warning: Color(0xFFDC6803),
    destructive: Color(0xFFA0452A),
    destructiveSubtle: Color(0xFFFEB9B3),
    info: Color(0xFF1570EF),
    link: Color(0xFF8A5A10),
    shadow: Color(0x143C2D14),
    focusRing: Color(0x800B0B0B),
    bgInverse: Color(0xFF2A241C),
    textPrimary: Color(0xFF1A1714),
    textInverse: Color(0xFFFBF7F0),
    textSecondary: Color(0xFF6E6053),
    textSubdued: Color(0xFF9A8B74),
    borderPrimary: Color(0x260B0B0B),
    borderSecondary: Color(0x1A0B0B0B),
    borderSubdued: Color(0x0D0B0B0B),
    buttonPrimary: Color(0xFF1A1714),
    buttonPrimaryHover: Color(0xFF2A241C),
    buttonDestructive: Color(0xFFEC2222),
    buttonDestructiveHover: Color(0xFFC91313),
    shadowXs: [BoxShadow(color: Color(0x143C2D14), offset: Offset(0.0, 1.0), blurRadius: 0.0, spreadRadius: 0.0)],
    shadowSm: [BoxShadow(color: Color(0x143C2D14), offset: Offset(0.0, 1.0), blurRadius: 0.0, spreadRadius: 0.0)],
    shadowMd: [BoxShadow(color: Color(0x733C2D14), offset: Offset(0.0, 4.0), blurRadius: 8.0, spreadRadius: -2.0)],
    shadowLg: [BoxShadow(color: Color(0x733C2D14), offset: Offset(0.0, 12.0), blurRadius: 16.0, spreadRadius: -4.0)],
    shadowXl: [BoxShadow(color: Color(0x733C2D14), offset: Offset(0.0, 20.0), blurRadius: 24.0, spreadRadius: -4.0)],
  );

  static const dark = SureTokenPalette(
    surface: Color(0xFF221D16),
    surfaceHover: Color(0xFF2A241C),
    surfaceInset: Color(0xFF1A140D),
    surfaceInsetHover: Color(0xFF2A241C),
    container: Color(0xFF2A241C),
    containerHover: Color(0xFF3B342A),
    containerInset: Color(0xFF1A140D),
    containerInsetHover: Color(0xFF3B342A),
    success: Color(0xFF32D583),
    warning: Color(0xFFFDB022),
    destructive: Color(0xFFD4664A),
    destructiveSubtle: Color(0xFFA40E0E),
    info: Color(0xFF2E90FA),
    link: Color(0xFFDDA761),
    shadow: Color(0x14FFFFFF),
    focusRing: Color(0x80FFFFFF),
    bgInverse: Color(0xFFFFFFFF),
    textPrimary: Color(0xFFEDE4D6),
    textInverse: Color(0xFF1A1714),
    textSecondary: Color(0xFFC79A5E),
    textSubdued: Color(0xFF9A8B74),
    borderPrimary: Color(0x4DFFFFFF),
    borderSecondary: Color(0x33FFFFFF),
    borderSubdued: Color(0x1AFFFFFF),
    buttonPrimary: Color(0xFFFFFFFF),
    buttonPrimaryHover: Color(0xFFF7F1E7),
    buttonDestructive: Color(0xFFED4E4E),
    buttonDestructiveHover: Color(0xFFF13636),
    shadowXs: [BoxShadow(color: Color(0x14FFFFFF), offset: Offset(0.0, 1.0), blurRadius: 2.0, spreadRadius: 0.0)],
    shadowSm: [BoxShadow(color: Color(0x14FFFFFF), offset: Offset(0.0, 1.0), blurRadius: 6.0, spreadRadius: 0.0)],
    shadowMd: [BoxShadow(color: Color(0x14FFFFFF), offset: Offset(0.0, 4.0), blurRadius: 8.0, spreadRadius: -2.0)],
    shadowLg: [BoxShadow(color: Color(0x14FFFFFF), offset: Offset(0.0, 12.0), blurRadius: 16.0, spreadRadius: -4.0)],
    shadowXl: [BoxShadow(color: Color(0x14FFFFFF), offset: Offset(0.0, 20.0), blurRadius: 24.0, spreadRadius: -4.0)],
  );
}

class SureTokenPalette {
  const SureTokenPalette({
    required this.surface,
    required this.surfaceHover,
    required this.surfaceInset,
    required this.surfaceInsetHover,
    required this.container,
    required this.containerHover,
    required this.containerInset,
    required this.containerInsetHover,
    required this.success,
    required this.warning,
    required this.destructive,
    required this.destructiveSubtle,
    required this.info,
    required this.link,
    required this.shadow,
    required this.focusRing,
    required this.bgInverse,
    required this.textPrimary,
    required this.textInverse,
    required this.textSecondary,
    required this.textSubdued,
    required this.borderPrimary,
    required this.borderSecondary,
    required this.borderSubdued,
    required this.buttonPrimary,
    required this.buttonPrimaryHover,
    required this.buttonDestructive,
    required this.buttonDestructiveHover,
    required this.shadowXs,
    required this.shadowSm,
    required this.shadowMd,
    required this.shadowLg,
    required this.shadowXl,
  });

  final Color surface;
  final Color surfaceHover;
  final Color surfaceInset;
  final Color surfaceInsetHover;
  final Color container;
  final Color containerHover;
  final Color containerInset;
  final Color containerInsetHover;
  final Color success;
  final Color warning;
  final Color destructive;
  final Color destructiveSubtle;
  final Color info;
  final Color link;
  final Color shadow;
  final Color focusRing;
  final Color bgInverse;
  final Color textPrimary;
  final Color textInverse;
  final Color textSecondary;
  final Color textSubdued;
  final Color borderPrimary;
  final Color borderSecondary;
  final Color borderSubdued;
  final Color buttonPrimary;
  final Color buttonPrimaryHover;
  final Color buttonDestructive;
  final Color buttonDestructiveHover;
  final List<BoxShadow> shadowXs;
  final List<BoxShadow> shadowSm;
  final List<BoxShadow> shadowMd;
  final List<BoxShadow> shadowLg;
  final List<BoxShadow> shadowXl;
}
