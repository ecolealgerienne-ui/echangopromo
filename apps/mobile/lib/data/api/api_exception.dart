import 'package:dio/dio.dart';
import '../../features/shared/errors/error_messages_fr.dart';

/// Erreur API normalisée — expose le `code` renvoyé par le backend NestJS
/// (`{ statusCode, code, message }`) en plus du message brut, pour permettre
/// un mapping code -> texte localisé côté mobile (préparation i18n) plutôt
/// que d'afficher tel quel le message backend.
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

    return ApiException(
      statusCode,
      null,
      "Impossible de contacter le serveur. Vérifiez votre connexion.",
    );
  }

  final int statusCode;
  final String? code;
  final String message;

  /// Texte à afficher : le mapping localisé du `code` s'il est connu, sinon
  /// le message backend brut — cas des erreurs de validation par champ
  /// (dynamiques, déjà en français côté backend) ou d'un code pas encore
  /// ajouté au mapping (voir error_messages_fr.dart).
  String get displayMessage => (code != null ? errorMessagesFr[code] : null) ?? message;

  @override
  String toString() => displayMessage;
}

/// L'intercepteur de [ApiClient] enveloppe toujours l'[ApiException] dans un
/// nouveau [DioException] (`.error`) — ce helper la retrouve depuis
/// n'importe quel `catch` d'appel API, sans dupliquer cette logique partout.
String extractApiErrorMessage(Object error, {required String fallback}) {
  if (error is DioException && error.error is ApiException) {
    return (error.error as ApiException).displayMessage;
  }
  return fallback;
}
