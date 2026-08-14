import 'dart:async';

import 'package:dio/dio.dart';

import '../local/etag_cache_store.dart';

/// Revalidation conditionnelle — l'`ETag` que le serveur servait sans preneur.
///
/// ── Le défaut que ça ferme ────────────────────────────────────────────────
///
/// Mesuré le 2026-08-13 : le backend pose un `ETag` sur toutes les réponses
/// JSON, et une requête conditionnelle obtient bien un `304`. Mais **aucun
/// paquet de cache HTTP n'existait dans `pubspec.yaml`** : Dio n'envoyait
/// jamais `If-None-Match`, donc cette capacité n'avait **aucun appelant**
/// (règle 31). Le serveur calculait un en-tête que personne ne lisait.
///
/// Chaque ouverture d'écran retéléchargeait 2,5 Ko pour la vitrine et 5,7 Ko
/// pour la carte, même quand rien n'avait changé.
///
/// ── ⚠️ Seuls les GET **non authentifiés** sont mis en cache ───────────────
///
/// C'est la règle qui rend ce cache sûr, et elle n'est pas un excès de
/// prudence. L'app est multi-rôles sur **un seul appareil** : le même téléphone
/// sert un client, puis un commerçant, puis un agent. Mettre en cache une
/// réponse authentifiée sous une clé d'URL ferait servir le tableau de bord
/// d'un compte à celui qui ouvre l'app ensuite — la clé ne porte pas l'identité.
///
/// Écarter tout ce qui porte `Authorization` supprime la question au lieu de la
/// gérer, et couvre exactement les trois routes publiques qui pèsent :
/// `/promo`, `/promo/map`, `/promo/config`.
///
/// ── ⚠️ Un `ETag` sans son corps est un piège ──────────────────────────────
///
/// Envoyer `If-None-Match` sans avoir le corps correspondant ferait répondre
/// `304` — « rien n'a changé, sers ce que tu as » — à une app qui n'a rien à
/// servir. [EtagCacheStore.lire] ne rend donc jamais l'un sans l'autre, et cet
/// intercepteur ne pose l'en-tête que s'il a les deux.
///
/// ── Pourquoi `onError` et non `onResponse` ────────────────────────────────
///
/// Dio traite `304` comme une **erreur** : son `validateStatus` par défaut
/// n'accepte que 200-299. La réponse conditionnelle arrive donc dans
/// `onError`, où `handler.resolve` la remplace par le corps conservé. C'est
/// contre-intuitif et c'est la raison pour laquelle cet intercepteur est
/// enregistré **avant** celui qui convertit les erreurs en `ApiException` :
/// sinon un `304` serait transformé en exception avant d'arriver ici.
class EtagCacheInterceptor extends Interceptor {
  EtagCacheInterceptor(this._store);

  final EtagCacheStore _store;

  /// ⚠️ `containsKey('Authorization')`, jamais une inspection du contenu : ce
  /// qui compte est qu'une identité soit en jeu, pas laquelle.
  bool _cachable(RequestOptions options) =>
      options.method.toUpperCase() == 'GET' &&
      !options.headers.containsKey('Authorization');

  /// L'URI complète — chemin **et** paramètres. Deux cadrages de carte
  /// différents sont deux réponses différentes ; les confondre servirait la
  /// mauvaise ville.
  String _cle(RequestOptions options) => options.uri.toString();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_cachable(options)) {
      final entree = _store.lire(_cle(options));
      if (entree != null) {
        options.headers['If-None-Match'] = entree.$1;
      }
    }
    handler.next(options);
  }

  @override
  void onResponse(
      Response<dynamic> response, ResponseInterceptorHandler handler) {
    final options = response.requestOptions;
    final etag = response.headers.value('etag');
    final corps = response.data;
    if (_cachable(options) &&
        response.statusCode == 200 &&
        etag != null &&
        corps != null) {
      // ⚠️ Non attendu : l'écriture dans les préférences ne doit pas retarder
      // l'affichage. Un cache qui ralentit la réponse qu'il conserve prend
      // l'exact contre-pied de son objectif.
      unawaited(_store.enregistrer(_cle(options), etag, corps as Object));
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final options = err.requestOptions;
    if (err.response?.statusCode == 304 && _cachable(options)) {
      final entree = _store.lire(_cle(options));
      if (entree != null) {
        handler.resolve(Response<dynamic>(
          requestOptions: options,
          statusCode: 200,
          data: entree.$2,
          headers: err.response?.headers,
        ));
        return;
      }
      // ⚠️ `304` sans corps conservé : l'entrée a été évincée entre la pose de
      // l'en-tête et la réponse. On laisse l'erreur suivre son cours plutôt
      // que d'inventer une réponse vide — un écran vide se lit comme « il n'y
      // a rien », ce qui est faux et indiscernable d'un produit cassé.
    }
    handler.next(err);
  }
}
