import 'package:dio/dio.dart';
import '../../config/env.dart';
import '../local/etag_cache_store.dart';
import 'api_exception.dart';
import 'etag_cache_interceptor.dart';

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
    EtagCacheStore? etagCache,
  }) : dio = Dio(BaseOptions(
          baseUrl: Env.apiBaseUrl,
          // Dio n'a par défaut aucun timeout (attente indéfinie) — sur la
          // couverture réseau variable du marché cible (audit performance
          // 2026-07-12), une requête sur une connexion dégradée laissait
          // l'utilisateur bloqué sur un spinner sans jamais échouer.
          // `StorageApi.uploadPhoto` (upload d'image, plus lent) surcharge
          // ces valeurs par requête plutôt que d'allonger le défaut global.
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 20),
        )) {
    // ⚠️ **L'ORDRE A ÉTÉ INVERSÉ LE 2026-08-14**, et le commentaire qui le
    // justifiait était faux. Il affirmait : « enregistré après, [le cache] ne
    // verrait jamais un seul 304 ». Contrefactuel mesuré pendant l'audit : dans
    // l'ordre inverse, le `304` anonyme est **toujours** resservi — l'`onError`
    // ci-dessous réémet une `DioException` avec `response` INTACT, que
    // `EtagCacheInterceptor` retrouve par `err.response?.statusCode == 304`.
    //
    // Ce que l'ancien ordre coûtait : Dio exécute `onRequest` en **FIFO**, donc
    // le cache jugeait AVANT que `Authorization` soit posé. Son test
    // `containsKey('Authorization')` rendait toujours faux, un `If-None-Match`
    // partait sur une requête authentifiée, le serveur rendait `304` — et comme
    // `onResponse`/`onError` jugent APRÈS, avec l'en-tête, le cache refusait de
    // resservir le corps conservé. Résultat mesuré : un écran **public** affichant
    // « Le serveur est momentanément indisponible » à un utilisateur connecté,
    // alors qu'il fonctionne parfaitement déconnecté.
    //
    // Le chemin est nominal, pas exotique : `splash_screen.dart` renvoie vers la
    // vitrine publique à CHAQUE lancement quelle que soit la session pro, et
    // `EtagCacheStore.vider()` n'a aucun appelant — l'entrée posée en session
    // anonyme survit à la connexion et au redémarrage.
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
    // ⚠️ Facultatif : les constructions qui n'ont pas de `SharedPreferences`
    // sous la main (tests unitaires) tournent simplement sans cache, plutôt
    // que d'imposer une dépendance à tout le monde pour une optimisation.
    if (etagCache != null) {
      dio.interceptors.add(EtagCacheInterceptor(etagCache));
    }
  }

  final Dio dio;
}
