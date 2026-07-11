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

  static const light = AppSemanticColors(success: Color(0xFF2F9E62), warning: Color(0xFFB45309));
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

/// Système de design "Chaleureux & communautaire" (terracotta/safran) —
/// piste choisie pour incarner le lien de quartier du pilote plutôt que les
/// codes visuels "app durable" vert/bleu. L'icône de l'app est recolorée
/// dans le même terracotta pour se distinguer des autres apps de la famille
/// echango (qui restent en teal) sur l'écran d'accueil.
class AppTheme {
  AppTheme._();

  static const _terracotta = Color(0xFFE8571E);
  static const _safran = Color(0xFFF2A93B);
  static const _surfaceLight = Color(0xFFFDF6EE);
  static const _surfaceDark = Color(0xFF211710);
  static const _errorLight = Color(0xFFD6303D);
  static const _errorDark = Color(0xFFF87171);

  static ThemeData get light => _build(brightness: Brightness.light);
  static ThemeData get dark => _build(brightness: Brightness.dark);

  static ThemeData _build({required Brightness brightness}) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: _terracotta,
      brightness: brightness,
      primary: _terracotta,
      secondary: _safran,
      surface: isDark ? _surfaceDark : _surfaceLight,
      error: isDark ? _errorDark : _errorLight,
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
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: colorScheme.onPrimary),
        iconTheme: IconThemeData(color: colorScheme.onPrimary),
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
