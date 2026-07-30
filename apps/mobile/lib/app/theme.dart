import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Rayons de coin de la piste "Chaleureux & communautaire" retenue pour le
/// design system (maquette de comparaison des 3 pistes validée avant
/// implémentation) : chips 8dp, boutons/champs 16dp, cartes/feuilles
/// modales 24dp.
class AppRadii {
  AppRadii._();

  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double pill = 999;
}

/// Durée de transition unique (≤180ms, easeOut) — la piste retenue
/// proscrit les animations spring/physics, coûteuses à interpoler sur les
/// appareils d'entrée de gamme visés par le pilote.
const kAppTransitionDuration = Duration(milliseconds: 180);

/// Couleurs sémantiques absentes du `ColorScheme` Material (qui n'a que
/// `error`) — succès et attention, déclinées clair/sombre.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({required this.success, required this.warning});

  final Color success;
  final Color warning;

  /// `warning` en ambre franc et non plus en ambre foncé (`0xFFB45309`) :
  /// les bandeaux d'alerte l'affichent à ~13 % d'opacité sur blanc, et un
  /// ambre trop sombre y produisait un beige — exactement le rendu « marron »
  /// qu'on cherchait à supprimer.
  static const light = AppSemanticColors(success: Color(0xFF2F9E62), warning: Color(0xFFD97706));
  static const dark = AppSemanticColors(success: Color(0xFF4ADE80), warning: Color(0xFFFBBF24));

  @override
  AppSemanticColors copyWith({Color? success, Color? warning}) {
    return AppSemanticColors(success: success ?? this.success, warning: warning ?? this.warning);
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}

/// Blanc franc, orange en accent (refonte 2026-07-29).
///
/// Le thème partait d'un `ColorScheme.fromSeed(seedColor: terracotta)` avec
/// seul `surface` surchargé. Insuffisant : `fromSeed` dérive **tous** les
/// autres tons de la graine, donc `onSurface`, `onSurfaceVariant`,
/// `outlineVariant`, les fonds de conteneur et surtout `surfaceTint` (qui
/// teinte en orange toute surface élevée) restaient bruns. Résultat, une
/// interface qui lisait « beige/marron » alors que seule la graine était
/// orange.
///
/// D'où des neutres **explicites**, indépendants de la graine : gris purs
/// côté surfaces et textes, et l'orange réservé à ce qui doit attirer l'œil
/// (prix, badges de réduction, sélection, boutons d'action). C'est cette
/// séparation stricte qui donne « fond blanc, détails orange » — pas un
/// simple éclaircissement de la teinte de fond.
class AppTheme {
  AppTheme._();

  static const _terracotta = Color(0xFFE8571E);
  static const _safran = Color(0xFFF2A93B);
  /// Orange plus clair sur fond sombre : le terracotta manque de contraste
  /// une fois posé sur du noir.
  static const _terracottaDark = Color(0xFFFF7A45);

  // --- Neutres clairs : gris purs, aucune trace de la graine orange ---
  static const _white = Color(0xFFFFFFFF);
  static const _ink = Color(0xFF1A1A1A);
  static const _inkMuted = Color(0xFF6B6B6B);
  static const _greyLowest = Color(0xFFFFFFFF);
  static const _greyLow = Color(0xFFFAFAFA);
  static const _grey = Color(0xFFF6F6F6);
  static const _greyHigh = Color(0xFFF1F1F1);
  static const _greyHighest = Color(0xFFEBEBEB);
  static const _outlineLight = Color(0xFFC9C9C9);
  static const _outlineVariantLight = Color(0xFFE6E6E6);

  /// Fond des pastilles et indicateurs orange pâle — le seul endroit où une
  /// surface est teintée, et volontairement (chip de catégorie sélectionnée,
  /// indicateur d'onglet).
  static const _orangeTintLight = Color(0xFFFFEDE4);
  static const _onOrangeTintLight = Color(0xFF8A2E06);

  // --- Neutres sombres : gris neutres également, plus de brun 0xFF211710 ---
  static const _surfaceDark = Color(0xFF141414);
  static const _inkDark = Color(0xFFECECEC);
  static const _inkMutedDark = Color(0xFFA8A8A8);
  static const _greyLowestDark = Color(0xFF0F0F0F);
  static const _greyLowDark = Color(0xFF1A1A1A);
  static const _greyDark = Color(0xFF1F1F1F);
  static const _greyHighDark = Color(0xFF262626);
  static const _greyHighestDark = Color(0xFF2E2E2E);
  static const _outlineDark = Color(0xFF5A5A5A);
  static const _outlineVariantDark = Color(0xFF303030);
  static const _orangeTintDark = Color(0xFF3D1B0C);
  static const _onOrangeTintDark = Color(0xFFFFCBB4);

  static const _errorLight = Color(0xFFD6303D);
  static const _errorDark = Color(0xFFF87171);

  static ThemeData get light => _build(brightness: Brightness.light);
  static ThemeData get dark => _build(brightness: Brightness.dark);

  static ThemeData _build({required Brightness brightness}) {
    final isDark = brightness == Brightness.dark;

    /// `ColorScheme` construit à la main plutôt que par `fromSeed` : c'est le
    /// seul moyen de garantir que pas un seul ton neutre ne soit dérivé de
    /// l'orange. Un `fromSeed(...).copyWith(...)` laisserait passer tout ton
    /// oublié, et il y en a une quinzaine.
    final colorScheme = isDark
        ? const ColorScheme.dark(
            primary: _terracottaDark,
            onPrimary: Color(0xFF3D1200),
            primaryContainer: _orangeTintDark,
            onPrimaryContainer: _onOrangeTintDark,
            secondary: _safran,
            onSecondary: Color(0xFF3D2A00),
            secondaryContainer: _orangeTintDark,
            onSecondaryContainer: _onOrangeTintDark,
            surface: _surfaceDark,
            onSurface: _inkDark,
            onSurfaceVariant: _inkMutedDark,
            surfaceContainerLowest: _greyLowestDark,
            surfaceContainerLow: _greyLowDark,
            surfaceContainer: _greyDark,
            surfaceContainerHigh: _greyHighDark,
            surfaceContainerHighest: _greyHighestDark,
            outline: _outlineDark,
            outlineVariant: _outlineVariantDark,
            error: _errorDark,
            onError: Color(0xFF3D0006),
            // Neutralise la teinte d'élévation Material 3 : sans ça, toute
            // carte ou feuille surélevée reprend un voile orange.
            surfaceTint: Colors.transparent,
          )
        : const ColorScheme.light(
            primary: _terracotta,
            onPrimary: _white,
            primaryContainer: _orangeTintLight,
            onPrimaryContainer: _onOrangeTintLight,
            secondary: _safran,
            onSecondary: _ink,
            secondaryContainer: _orangeTintLight,
            onSecondaryContainer: _onOrangeTintLight,
            surface: _white,
            onSurface: _ink,
            onSurfaceVariant: _inkMuted,
            surfaceContainerLowest: _greyLowest,
            surfaceContainerLow: _greyLow,
            surfaceContainer: _grey,
            surfaceContainerHigh: _greyHigh,
            surfaceContainerHighest: _greyHighest,
            outline: _outlineLight,
            outlineVariant: _outlineVariantLight,
            error: _errorLight,
            onError: _white,
            surfaceTint: Colors.transparent,
          );

    final textTheme = _textTheme(colorScheme);
    final outline = colorScheme.outlineVariant;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      textTheme: textTheme,
      extensions: [isDark ? AppSemanticColors.dark : AppSemanticColors.light],
      // Barre blanche, titre en encre, icônes orange. Une barre pleine
      // orange en tête de chaque écran pro ferait de l'orange la couleur
      // dominante, pas un détail — l'inverse de l'intention.
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: colorScheme.onSurface),
        iconTheme: IconThemeData(color: colorScheme.primary),
        actionsIconTheme: IconThemeData(color: colorScheme.primary),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primaryContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      dividerTheme: DividerThemeData(color: outline, thickness: 1),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          side: BorderSide(color: outline),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
        side: BorderSide(color: outline),
        selectedColor: colorScheme.primary,
        backgroundColor: colorScheme.surface,
        labelStyle: textTheme.labelLarge,
        secondaryLabelStyle: textTheme.labelLarge?.copyWith(color: colorScheme.onPrimary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
        filled: true,
        fillColor: colorScheme.surface,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          textStyle: textTheme.labelLarge,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          textStyle: textTheme.labelLarge,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.onSurface,
          side: BorderSide(color: outline),
          textStyle: textTheme.labelLarge,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          textStyle: textTheme.labelLarge,
        ),
      ),
    );
  }

  static TextTheme _textTheme(ColorScheme colorScheme) {
    TextStyle title(double size, double lineHeight, FontWeight weight) => GoogleFonts.cairo(
          fontSize: size,
          height: lineHeight / size,
          fontWeight: weight,
          color: colorScheme.onSurface,
        );

    TextStyle body(double size, double lineHeight, FontWeight weight) =>
        GoogleFonts.ibmPlexSansArabic(
          fontSize: size,
          height: lineHeight / size,
          fontWeight: weight,
          color: colorScheme.onSurface,
        );

    return TextTheme(
      displayLarge: title(40, 46, FontWeight.w700),
      displayMedium: title(34, 40, FontWeight.w700),
      displaySmall: title(30, 36, FontWeight.w700),
      headlineLarge: title(32, 38, FontWeight.w700),
      // H1 (28/34, Cairo 700) de la piste retenue.
      headlineMedium: title(28, 34, FontWeight.w700),
      headlineSmall: title(24, 30, FontWeight.w700),
      // H2 (22/28, Cairo 600).
      titleLarge: title(22, 28, FontWeight.w600),
      // H3 (18/24, Cairo 600).
      titleMedium: title(18, 24, FontWeight.w600),
      titleSmall: title(16, 22, FontWeight.w600),
      bodyLarge: body(16, 24, FontWeight.w400),
      // Corps (15/22, Plex Sans Arabic 400).
      bodyMedium: body(15, 22, FontWeight.w400),
      // Caption (12/16, Plex Sans Arabic 400).
      bodySmall: body(12, 16, FontWeight.w400),
      // Bouton/label (14/20, Plex Sans Arabic 500).
      labelLarge: body(14, 20, FontWeight.w500),
      labelMedium: body(12, 16, FontWeight.w500),
      labelSmall: body(11, 14, FontWeight.w500),
    );
  }
}
