final RegExp _pinPattern = RegExp(r'^\d{4,6}$');

/// Miroir de la regex backend (`^\d{4,6}$`, decision produit tranchée :
/// 4 à 6 chiffres, cf. specs §3.2) — pas seulement une longueur minimale.
String? validatePin(String? value) {
  if (value == null || !_pinPattern.hasMatch(value)) {
    return 'Le code PIN doit contenir 4 à 6 chiffres';
  }
  return null;
}
