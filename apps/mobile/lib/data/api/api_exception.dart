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
      final message =
          rawMessage is List ? rawMessage.join(', ') : rawMessage.toString();
      final code = data['code'] as String?;
      return ApiException(statusCode, code, message);
    }

    // ⚠️ Deux causes distinctes, deux codes — un repli unique détruisait
    // l'information qui compte (règle #29). « Rien reçu » et « reçu quelque
    // chose d'illisible » n'appellent pas le même geste : un 502 en text/html
    // renvoyé par le frontal Traefik affichait « Vérifiez votre connexion »,
    // envoyant l'utilisateur couper sa 4G et conclure que l'app est cassée,
    // alors que son réseau marchait et que la panne était côté serveur
    // (revue 2026-08-05). Ni l'un ni l'autre n'est un `ErrorCode` backend :
    // les deux sont localisés côté app (voir `error_messages_fr.dart`).
    if (error.response != null) {
      return ApiException(
        statusCode,
        'SERVER_UNAVAILABLE',
        'Le serveur est momentanément indisponible. Réessayez dans un instant.',
      );
    }
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
    final messages =
        _errorMessagesByLocale[locale.languageCode] ?? errorMessagesFr;
    return messages[code] ?? message;
  }

  @override
  String toString() => displayMessage(const Locale('fr'));
}

/// L'intercepteur de [ApiClient] enveloppe toujours l'[ApiException] dans un
/// nouveau [DioException] (`.error`) — ce helper la retrouve depuis
/// n'importe quel `catch` d'appel API, sans dupliquer cette logique partout.
String extractApiErrorMessage(Object error,
    {required String fallback, required Locale locale}) {
  if (error is DioException && error.error is ApiException) {
    return (error.error as ApiException).displayMessage(locale);
  }
  return fallback;
}

/// Le `code` backend d'une erreur d'appel API, ou `null` si l'erreur n'en
/// porte pas.
///
/// ⚠️ **Le même enveloppement piège tout `catch` qui raisonne sur le code.**
/// Un `on ApiException catch` ne matche jamais : l'intercepteur rend une
/// [DioException] dont `.error` porte l'[ApiException]. *Trouvé le 2026-08-05
/// en ouvrant l'espace pro aux agents — le repli « admin refusé, essayons
/// agent » ne s'est jamais déclenché, et l'écran affichait « Identifiants
/// invalides » sur des identifiants parfaitement valides.*
///
/// Rendre `null` plutôt qu'une chaîne vide : « pas de code » et « code vide »
/// n'appellent pas le même geste (règle #29).
String? apiErrorCode(Object error) {
  if (error is DioException && error.error is ApiException) {
    return (error.error as ApiException).code;
  }
  return null;
}
