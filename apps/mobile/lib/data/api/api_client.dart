import 'package:dio/dio.dart';
import '../../config/env.dart';
import 'api_exception.dart';

/// Codes renvoyés par le backend quand le token JWT n'est plus utilisable
/// (absent, invalide/expiré, ou révoqué via tokenVersion) — dans tous ces
/// cas la session locale est déconnectée, sinon l'utilisateur reste bloqué
/// sur son écran avec un token mort tant qu'il ne trouve pas le bouton
/// logout manuel (audit V1 §8).
const _authInvalidCodes = {
  'AUTH_TOKEN_MISSING',
  'AUTH_TOKEN_INVALID',
  'AUTH_TOKEN_REVOKED',
};

/// Client HTTP partagé : ajoute systématiquement le device ID anonyme
/// (specs §3.1/§5.4) et le token JWT s'il y a une session active. Les
/// erreurs Dio sont converties en [ApiException] pour un affichage simple.
class ApiClient {
  ApiClient({
    required String Function() getDeviceId,
    required String? Function() getToken,
    void Function()? onAuthInvalid,
  }) : dio = Dio(BaseOptions(baseUrl: Env.apiBaseUrl)) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.headers['X-Device-Id'] = getDeviceId();
          final token = getToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) {
          final apiException = ApiException.fromDioError(error);
          if (_authInvalidCodes.contains(apiException.code)) {
            onAuthInvalid?.call();
          }
          handler.next(DioException(
            requestOptions: error.requestOptions,
            response: error.response,
            error: apiException,
            type: error.type,
          ));
        },
      ),
    );
  }

  final Dio dio;
}
