import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import '../../features/shared/errors/error_messages_ar.dart';
import '../../features/shared/errors/error_messages_en.dart';
import '../../features/shared/errors/error_messages_fr.dart';

const _errorMessagesByLocale = {
  'fr': errorMessagesFr,
  'en': errorMessagesEn,
  'ar': errorMessagesAr,
};

/// Erreur API normalisée — expose le `code` renvoyé par le backend NestJS
/// (`{ statusCode, code, message }`) en plus du message brut, pour permettre
/// un mapping code -> texte localisé côté mobile (i18n FR/EN/AR) plutôt que
/// d'afficher tel quel le message backend (toujours en français).
class ApiException implements Exception {
  ApiException(this.statusCode, this.code, this.message);

  factory ApiException.fromDioError(DioException error) {
    final data = error.response?.data;
    final statusCode = error.response?.statusCode ?? 0;

    if (data is Map && data['message'] != null) {
      final rawMessage = data['message'];
      final message = rawMessage is List ? rawMessage.join(', ') : rawMessage.toString();
      final code = data['code'] as String?;
      return ApiException(statusCode, code, message);
    }

    // Pas de réponse HTTP du tout (hors ligne, timeout...) — code dédié,
    // non émis par le backend, pour rester localisable comme les autres
    // (voir `error_messages_fr.dart`).
    return ApiException(
      statusCode,
      'NETWORK_ERROR',
      'Impossible de contacter le serveur. Vérifiez votre connexion.',
    );
  }

  final int statusCode;
  final String? code;
  final String message;

  /// Texte à afficher dans la langue `locale` : le mapping localisé du
  /// `code` s'il est connu, sinon le message backend brut (toujours en
  /// français) — cas des erreurs de validation par champ (dynamiques) ou
  /// d'un code pas encore ajouté aux mappings.
  String displayMessage(Locale locale) {
    if (code == null) return message;
    final messages = _errorMessagesByLocale[locale.languageCode] ?? errorMessagesFr;
    return messages[code] ?? message;
  }

  @override
  String toString() => displayMessage(const Locale('fr'));
}

/// L'intercepteur de [ApiClient] enveloppe toujours l'[ApiException] dans un
/// nouveau [DioException] (`.error`) — ce helper la retrouve depuis
/// n'importe quel `catch` d'appel API, sans dupliquer cette logique partout.
String extractApiErrorMessage(Object error, {required String fallback, required Locale locale}) {
  if (error is DioException && error.error is ApiException) {
    return (error.error as ApiException).displayMessage(locale);
  }
  return fallback;
}
