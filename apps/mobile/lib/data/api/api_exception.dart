import 'package:dio/dio.dart';

/// Erreur API normalisée — expose le message renvoyé par le backend NestJS
/// (`{ message, error, statusCode }`) plutôt que le message générique Dio.
class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  factory ApiException.fromDioError(DioException error) {
    final data = error.response?.data;
    final statusCode = error.response?.statusCode ?? 0;

    if (data is Map && data['message'] != null) {
      final rawMessage = data['message'];
      final message = rawMessage is List ? rawMessage.join(', ') : rawMessage.toString();
      return ApiException(statusCode, message);
    }

    return ApiException(statusCode, "Impossible de contacter le serveur. Vérifiez votre connexion.");
  }

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

/// L'intercepteur de [ApiClient] enveloppe toujours l'[ApiException] dans un
/// nouveau [DioException] (`.error`) — ce helper la retrouve depuis
/// n'importe quel `catch` d'appel API, sans dupliquer cette logique partout.
String extractApiErrorMessage(Object error, {required String fallback}) {
  if (error is DioException && error.error is ApiException) {
    return (error.error as ApiException).message;
  }
  return fallback;
}
