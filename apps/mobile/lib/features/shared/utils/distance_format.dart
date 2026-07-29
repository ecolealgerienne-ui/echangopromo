import '../../../l10n/app_localizations.dart';

/// Distance lisible : en mètres arrondis à la dizaine sous 1 km, en
/// kilomètres à une décimale au-delà. Un « 847 m » affiché au mètre près
/// donnerait une fausse impression de précision — la position d'un
/// commerçant est saisie à la main, pas relevée au GPS différentiel.
String formatDistance(AppLocalizations l10n, double meters) {
  if (meters < 1000) {
    final rounded = (meters / 10).round() * 10;
    return l10n.distanceMeters(rounded);
  }
  return l10n.distanceKilometers((meters / 1000).toStringAsFixed(1));
}
