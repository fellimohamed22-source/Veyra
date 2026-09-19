import 'package:flutter/material.dart';

/// Design tokens centralisés — Veyra Design System.
///
/// Ces valeurs ne sont PAS inventées : elles ont été extraites du code
/// existant (mobile-client/mobile-driver main.dart, avant ce lot) et des
/// maquettes annotées du kit UI (VEYRA_MVP_UI_KIT_CLAUDE_V3). L'objectif
/// de ce fichier est de centraliser des valeurs déjà en usage dispersé,
/// pas de changer la direction visuelle.
class VeyraColors {
  VeyraColors._();

  // Brand
  static const primary = Color(0xFF1565C0);
  static const primaryDark = Color(0xFF123A66);

  // Neutrals
  static const background = Color(0xFFF2F6FB);
  static const surface = Colors.white;
  static const textPrimary = Color(0xFF1F2937);
  static const textSecondary = Color(0xFF6B7280);
  static const textTertiary = Color(0xFF9CA3AF);
  static const border = Color(0xFFE5E7EB);

  // Semantic
  static const success = Color(0xFF12883E);
  static const successBackground = Color(0xFFE8F7EE);
  static const info = Color(0xFF2563EB);
  static const infoBackground = Color(0xFFEAF1FD);
  static const warning = Color(0xFFA46907);
  static const warningBackground = Color(0xFFFDF3E3);
  static const danger = Color(0xFFDC2626);
  static const dangerBackground = Color(0xFFFDEAEA);
  static const neutral = Color(0xFF6B7280);
  static const neutralBackground = Color(0xFFF3F4F6);
}

/// Échelle 4/8pt déjà suivie de façon informelle dans le code existant
/// (EdgeInsets.all(4/8/12/16/20/24) très majoritaires) — formalisée ici.
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

/// Rayons déjà utilisés : cartes 12-16, pills/CTA 20-24.
class VeyraRadius {
  VeyraRadius._();
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const pill = 24.0;
  static const card = 20.0;
}

class VeyraShadows {
  VeyraShadows._();
  static List<BoxShadow> card = [
    BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2)),
  ];
}

ThemeData veyraTheme() {
  return ThemeData(
    useMaterial3: true,
    colorSchemeSeed: VeyraColors.primary,
    scaffoldBackgroundColor: VeyraColors.background,
    fontFamily: null, // système par défaut — aucune police custom n'était utilisée avant ce lot.
    appBarTheme: const AppBarTheme(
      backgroundColor: VeyraColors.background,
      foregroundColor: VeyraColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(color: VeyraColors.primaryDark,fontSize:20,fontWeight:FontWeight.w800,letterSpacing:-0.2),
    ),
    cardTheme: CardThemeData(
      color: VeyraColors.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VeyraRadius.card),side: const BorderSide(color: VeyraColors.border)),
      margin: EdgeInsets.zero,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: VeyraColors.surface,
      indicatorColor: VeyraColors.infoBackground,
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith((states)=>TextStyle(color:states.contains(WidgetState.selected)?VeyraColors.primary:VeyraColors.textSecondary,fontSize:12,fontWeight:states.contains(WidgetState.selected)?FontWeight.w800:FontWeight.w600)),
      iconTheme: WidgetStateProperty.resolveWith((states)=>IconThemeData(color:states.contains(WidgetState.selected)?VeyraColors.primary:VeyraColors.textSecondary)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(backgroundColor:VeyraColors.primary,foregroundColor:Colors.white,disabledBackgroundColor:VeyraColors.border,disabledForegroundColor:VeyraColors.textTertiary,minimumSize:const Size.fromHeight(54),elevation:0,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(VeyraRadius.md)),textStyle:const TextStyle(fontWeight:FontWeight.w800,fontSize:16)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(backgroundColor:VeyraColors.primary,foregroundColor:Colors.white,minimumSize:const Size.fromHeight(52),elevation:0,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(VeyraRadius.md)),textStyle:const TextStyle(fontWeight:FontWeight.w800,fontSize:15)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(foregroundColor:VeyraColors.primary,minimumSize:const Size.fromHeight(50),side:const BorderSide(color:VeyraColors.border),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(VeyraRadius.md)),textStyle:const TextStyle(fontWeight:FontWeight.w700,fontSize:15)),
    ),
    snackBarTheme: SnackBarThemeData(behavior:SnackBarBehavior.floating,backgroundColor:VeyraColors.textPrimary,contentTextStyle:const TextStyle(color:Colors.white,fontWeight:FontWeight.w600),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(VeyraRadius.md))),
    dividerTheme:const DividerThemeData(color:VeyraColors.border,space:1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: VeyraColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: VeyraSpacing.lg, vertical: VeyraSpacing.md),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(VeyraRadius.md),
        borderSide: const BorderSide(color: VeyraColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(VeyraRadius.md),
        borderSide: const BorderSide(color: VeyraColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(VeyraRadius.md),
        borderSide: const BorderSide(color: VeyraColors.primary, width: 2),
      ),
    ),
  );
}
