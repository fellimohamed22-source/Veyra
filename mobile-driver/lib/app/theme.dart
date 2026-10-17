import 'package:flutter/material.dart';

/// Design tokens VEYRA V4 (DEC-12), relevés sur les 17 planches de
/// maquettes par échantillonnage (voir docs/v4/INDEX_MAQUETTES_CORRIGE.md) :
/// bleu marine des boutons et en-têtes, bleu vif des liens et épingles,
/// or des actions décisives, fond blanc, cartes gris très clair.
/// Les noms historiques (primary, primaryDark...) sont conservés pour que
/// tout le code existant bascule sur la nouvelle palette.
class VeyraColors {
  VeyraColors._();

  // Marque
  static const primary = Color(0xFF021C38); // marine : boutons, titres (M01, M05, M06)
  static const primaryDark = Color(0xFF021C38);
  static const accent = Color(0xFF0C6CFD); // bleu vif : liens, position, épingle départ (M01)
  static const goldStart = Color(0xFFD7A86A); // dégradé or : « Confirmer la réservation » (M03)
  static const goldEnd = Color(0xFFC37E32);
  static const pinRed = Color(0xFFE5342E); // épingle destination (M01, M09)

  // Neutres
  static const background = Color(0xFFFFFFFF);
  static const surface = Colors.white;
  static const surfaceMuted = Color(0xFFF5F7FA); // lignes « Utiliser ma position », compteurs
  static const textPrimary = Color(0xFF0E1A2B);
  static const textSecondary = Color(0xFF5B6576);
  static const textTertiary = Color(0xFF8A94A6);
  static const border = Color(0xFFE6E9EF);

  // États (assombris pour un contraste AA du texte)
  static const success = Color(0xFF2E7D4F);
  static const successBackground = Color(0xFFE3F6EA);
  static const info = Color(0xFF0C6CFD);
  static const infoBackground = Color(0xFFE8F0FE);
  static const warning = Color(0xFF8A5806);
  static const warningBackground = Color(0xFFF9EED3);
  static const danger = Color(0xFFD92D34);
  static const dangerBackground = Color(0xFFFDE8E9);
  static const neutral = Color(0xFF6B7280);
  static const neutralBackground = Color(0xFFF1F3F6);

  static const goldGradient = LinearGradient(colors: [goldStart, goldEnd], begin: Alignment.topLeft, end: Alignment.bottomRight);
}

class VeyraSpacing {
  VeyraSpacing._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
}

/// Rayons estimés sur les planches (à confirmer par mesure, DEC-12).
class VeyraRadius {
  VeyraRadius._();
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const pill = 999.0;
  static const card = 16.0;
}

class VeyraShadows {
  VeyraShadows._();
  static List<BoxShadow> card = [
    BoxShadow(color: const Color(0xFF021C38).withValues(alpha: 0.06), blurRadius: 14, offset: const Offset(0, 4)),
    BoxShadow(color: const Color(0xFF021C38).withValues(alpha: 0.04), blurRadius: 2, offset: const Offset(0, 1)),
  ];
}

const veyraFontFamily = 'PlusJakartaSans';

ThemeData veyraTheme() {
  const text = TextTheme(
    headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: VeyraColors.textPrimary, letterSpacing: -0.3),
    titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: VeyraColors.textPrimary),
    titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: VeyraColors.textPrimary),
    titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: VeyraColors.textPrimary),
    bodyLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: VeyraColors.textPrimary),
    bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: VeyraColors.textPrimary),
    bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: VeyraColors.textSecondary),
    labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
  );
  return ThemeData(
    useMaterial3: true,
    fontFamily: veyraFontFamily,
    textTheme: text,
    colorScheme: ColorScheme.fromSeed(seedColor: VeyraColors.primary).copyWith(
      primary: VeyraColors.primary,
      onPrimary: Colors.white,
      secondary: VeyraColors.accent,
      surface: VeyraColors.surface,
      error: VeyraColors.danger,
    ),
    scaffoldBackgroundColor: VeyraColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: VeyraColors.background,
      foregroundColor: VeyraColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(fontFamily: veyraFontFamily, color: VeyraColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
    ),
    cardTheme: CardThemeData(
      color: VeyraColors.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VeyraRadius.card), side: const BorderSide(color: VeyraColors.border)),
      margin: EdgeInsets.zero,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: VeyraColors.surface,
      indicatorColor: Colors.transparent,
      elevation: 0,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(fontFamily: veyraFontFamily, color: s.contains(WidgetState.selected) ? VeyraColors.primary : VeyraColors.textTertiary, fontSize: 11, fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500)),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? VeyraColors.primary : VeyraColors.textTertiary, size: 24)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(backgroundColor: VeyraColors.primary, foregroundColor: Colors.white, disabledBackgroundColor: const Color(0xFFB8C1CE), disabledForegroundColor: Colors.white, minimumSize: const Size.fromHeight(54), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VeyraRadius.md)), textStyle: const TextStyle(fontFamily: veyraFontFamily, fontWeight: FontWeight.w700, fontSize: 16)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(backgroundColor: VeyraColors.primary, foregroundColor: Colors.white, disabledBackgroundColor: const Color(0xFFB8C1CE), disabledForegroundColor: Colors.white, minimumSize: const Size.fromHeight(54), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VeyraRadius.md)), textStyle: const TextStyle(fontFamily: veyraFontFamily, fontWeight: FontWeight.w700, fontSize: 16)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(foregroundColor: VeyraColors.primary, backgroundColor: Colors.white, minimumSize: const Size.fromHeight(54), side: const BorderSide(color: VeyraColors.border), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VeyraRadius.md)), textStyle: const TextStyle(fontFamily: veyraFontFamily, fontWeight: FontWeight.w700, fontSize: 15)),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: VeyraColors.accent, textStyle: const TextStyle(fontFamily: veyraFontFamily, fontWeight: FontWeight.w600, fontSize: 14)),
    ),
    chipTheme: const ChipThemeData(backgroundColor: VeyraColors.surfaceMuted, side: BorderSide.none, labelStyle: TextStyle(fontFamily: veyraFontFamily, color: VeyraColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: VeyraColors.primary, contentTextStyle: const TextStyle(fontFamily: veyraFontFamily, color: Colors.white, fontWeight: FontWeight.w600), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VeyraRadius.md))),
    dividerTheme: const DividerThemeData(color: VeyraColors.border, space: 1),
    checkboxTheme: CheckboxThemeData(fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? VeyraColors.accent : null)),
    radioTheme: RadioThemeData(fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? VeyraColors.accent : VeyraColors.textTertiary)),
    switchTheme: SwitchThemeData(trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? const Color(0xFF34C759) : null), thumbColor: const WidgetStatePropertyAll(Colors.white)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: VeyraColors.surface,
      hintStyle: const TextStyle(color: VeyraColors.textTertiary, fontWeight: FontWeight.w500),
      contentPadding: const EdgeInsets.symmetric(horizontal: VeyraSpacing.lg, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(VeyraRadius.md), borderSide: const BorderSide(color: VeyraColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(VeyraRadius.md), borderSide: const BorderSide(color: VeyraColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(VeyraRadius.md), borderSide: const BorderSide(color: VeyraColors.accent, width: 1.6)),
    ),
  );
}
