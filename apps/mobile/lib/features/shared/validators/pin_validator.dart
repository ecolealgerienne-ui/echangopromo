import 'package:flutter/widgets.dart';
import '../../../l10n/app_localizations.dart';

final RegExp _pinPattern = RegExp(r'^\d{4,6}$');

/// Miroir de la regex backend (`^\d{4,6}$`, decision produit tranchée :
/// 4 à 6 chiffres, cf. specs §3.2) — pas seulement une longueur minimale.
/// Retourne le validateur `TextFormField` lié au `context` courant, pour
/// afficher le message d'erreur dans la langue choisie par l'utilisateur.
String? Function(String?) validatePin(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  return (value) {
    if (value == null || !_pinPattern.hasMatch(value)) {
      return l10n.pinRule;
    }
    return null;
  };
}
