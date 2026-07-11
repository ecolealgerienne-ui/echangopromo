import 'package:flutter/material.dart';
import '../../../data/api/api_exception.dart';
import '../../../l10n/app_localizations.dart';

/// Message d'erreur pour un `AsyncValue.when(error: ...)` — extrait le
/// message localisé de l'[ApiException] enveloppée par `ApiClient` au lieu
/// d'afficher `error.toString()` brut. `DioException.toString()` ajoute lui-
/// même un `\nError: $error` (implémentation du package dio), donc l'ancien
/// pattern `Text(l10n.commonError(error.toString()))`, répété tel quel dans
/// une quinzaine d'écrans, affichait deux lignes : le dump technique Dio
/// ("DioException [bad response]: null") suivi du vrai message métier —
/// visible dans l'app malgré `extractApiErrorMessage` qui existe déjà pour
/// ce cas, simplement jamais branché sur les erreurs de chargement (seules
/// les actions de bouton l'utilisaient).
class ApiErrorText extends StatelessWidget {
  const ApiErrorText(this.error, {super.key});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final message = extractApiErrorMessage(
      error,
      fallback: l10n.operationFailed,
      locale: Localizations.localeOf(context),
    );
    return Text(l10n.commonError(message));
  }
}
