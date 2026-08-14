import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Cache de revalidation HTTP — l'`ETag` et le corps qui va avec.
///
/// ── Ce que ce store est, et ce qu'il n'est pas ────────────────────────────
///
/// Ce n'est **pas** un cache hors ligne : rien n'est servi depuis ici sans que
/// le serveur ait confirmé, par un `304`, que le corps conservé est toujours le
/// bon. C'est un cache de **bande passante**, pas de disponibilité.
///
/// La distinction n'est pas théorique. Un cache qui sert du contenu sans
/// demander l'avis du serveur montrerait des promos retirées par la modération,
/// et ce produit retire des arnaques : la fraîcheur n'y est pas négociable.
/// C'est aussi pourquoi les routes portent `max-age=0, must-revalidate` côté
/// serveur — on paie l'aller-retour à chaque fois, on n'économise que le corps.
///
/// ── ⚠️ L'`ETag` et le corps sont indissociables ───────────────────────────
///
/// Conserver un `ETag` sans son corps serait pire que ne rien conserver :
/// l'app enverrait `If-None-Match`, recevrait `304` — « rien n'a changé, sers
/// ce que tu as » — et n'aurait **rien à servir**. Les deux se posent et se
/// retirent ensemble, exactement comme le point et son consentement dans
/// `ClientPositionStore`.
///
/// ── Les deux bornes, et pourquoi elles existent ───────────────────────────
///
/// `SharedPreferences` est un fichier lu **en entier au démarrage**. Y laisser
/// grossir des corps de réponse ralentirait le lancement de l'app — soit
/// exactement ce qu'on cherche à améliorer. D'où un plafond par entrée et un
/// plafond en nombre d'entrées, avec éviction de la plus ancienne.
class EtagCacheStore {
  EtagCacheStore(this._prefs);

  static const _indexKey = 'etag_cache_index';
  static const _prefixe = 'etag_cache_';

  /// ⚠️ Au-delà, on ne conserve pas : le gain de bande passante ne vaut pas un
  /// démarrage alourdi. Les deux réponses visées pèsent 2,5 et 5,7 Ko
  /// compressés (mesuré le 2026-08-13) — très en dessous.
  static const maxOctetsParEntree = 64 * 1024;

  /// Assez pour la vitrine, la carte à quelques cadrages, la configuration et
  /// les fiches consultées dans une session. Au-delà, la plus ancienne part.
  static const maxEntrees = 24;

  final SharedPreferences _prefs;

  /// `null` tant que l'un des deux manque — voir l'invariant ci-dessus.
  (String etag, Object corps)? lire(String cle) {
    final brut = _prefs.getString(_prefixe + cle);
    if (brut == null) return null;
    try {
      final json = jsonDecode(brut) as Map<String, dynamic>;
      final etag = json['etag'] as String?;
      final corps = json['corps'];
      if (etag == null || corps == null) return null;
      return (etag, corps as Object);
    } catch (_) {
      // Entrée illisible (format changé, écriture interrompue) : on l'oublie
      // plutôt que de propager une exception depuis un cache. Un cache qui
      // fait échouer la requête qu'il devait accélérer est pire que pas de
      // cache du tout.
      return null;
    }
  }

  Future<void> enregistrer(String cle, String etag, Object corps) async {
    final String encode;
    try {
      encode = jsonEncode({'etag': etag, 'corps': corps});
    } catch (_) {
      return; // Corps non sérialisable (binaire) : hors périmètre.
    }
    if (encode.length > maxOctetsParEntree) return;

    final index = _prefs.getStringList(_indexKey) ?? <String>[];
    index.remove(cle);
    index.add(cle);
    while (index.length > maxEntrees) {
      await _prefs.remove(_prefixe + index.removeAt(0));
    }
    await _prefs.setString(_prefixe + cle, encode);
    await _prefs.setStringList(_indexKey, index);
  }

  /// Vide le cache — appelé quand la session change de rôle, pour qu'aucune
  /// réponse conservée sous un profil ne survive au suivant.
  Future<void> vider() async {
    for (final cle in _prefs.getStringList(_indexKey) ?? <String>[]) {
      await _prefs.remove(_prefixe + cle);
    }
    await _prefs.remove(_indexKey);
  }
}
