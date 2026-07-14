import 'package:flutter/widgets.dart';
import '../../../l10n/app_localizations.dart';

final RegExp _pinSetPattern = RegExp(r'^\d{6,12}$');
final RegExp _pinVerifyPattern = RegExp(r'^\d{4,12}$');

/// Miroir de la regex backend `PIN_SET_PATTERN` (`^\d{6,12}$`, décision
/// produit 2026-07-13 — relevé de 4-6 à 6-12 chiffres en fermant la
/// revendication publique de compte) — à utiliser pour toute opération qui
/// **fixe** un PIN (inscription, création par l'agent, changement,
/// réinitialisation). Retourne le validateur `TextFormField` lié au
/// `context` courant, pour afficher le message d'erreur dans la langue
/// choisie par l'utilisateur.
String? Function(String?) validatePin(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  return (value) {
    if (value == null || !_pinSetPattern.hasMatch(value)) {
      return l10n.pinRule;
    }
    return null;
  };
}

/// Miroir de `PIN_VERIFY_PATTERN` (`^\d{4,12}$`) — utilisé pour saisir un
/// PIN déjà existant (connexion, ancien PIN d'un changement) : reste
/// permissif sur 4-12 chiffres pour ne pas rejeter un PIN fixé avant le
/// relèvement du minimum à 6, sous peine de bloquer silencieusement l'accès
/// des commerçants déjà actifs.
String? Function(String?) validateExistingPin(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  return (value) {
    if (value == null || !_pinVerifyPattern.hasMatch(value)) {
      return l10n.pinVerifyRule;
    }
    return null;
  };
}
