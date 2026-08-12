import 'package:shared_preferences/shared_preferences.dart';

/// Version du texte présenté au client au moment où il enregistre son point.
///
/// ⚠️ **Sans elle, on sait *qu'*on a consenti, jamais *à quoi*.** Aucun
/// re-consentement ne serait possible quand le texte change — alors que le §7
/// des CGU annonce lui-même qu'elles évolueront. C'était un trou complet du
/// produit : recherche `cguVersion|termsVersion|legalVersion|consentVersion`
/// sur tout le dépôt, zéro résultat (revue du 2026-08-12).
const kPositionConsentVersion = 'geo-2026-08-12';

/// Le point de recherche du client, et son consentement — **inséparables**.
///
/// ── Ce que ce store contient, et ce qu'il ne contient pas ─────────────────
///
/// Il contient **un point que le client a choisi et enregistré**, pas une
/// lecture de capteur. Le GPS peut servir à le trouver (on se centre sur soi
/// puis on enregistre), mais rien n'est écrit ici sans un geste explicite : il
/// n'existe aucun chemin où accorder la permission de localisation suffirait à
/// remplir ce store. Cette frontière est ce qui permet d'affirmer aux deux
/// stores qu'il n'y a **ni suivi, ni lecture en arrière-plan, ni historique**
/// (voir `docs/PLAN_BASCULE_GEO.md` §2.1 et §2.2).
///
/// ── Pourquoi le consentement n'est pas un troisième champ indépendant ─────
///
/// Parce que le geste d'enregistrement **est** le consentement : le client
/// choisit un point, on lui dit à ce moment-là qu'il sera envoyé au service
/// pour construire sa liste, il valide. Un écran de consentement séparé serait
/// de la friction pour une donnée qu'il vient de saisir dans ce but précis.
///
/// D'où l'invariant tenu ici : **point et consentement se posent ensemble et
/// se retirent ensemble**. Il rend la porte triviale à vérifier — on émet des
/// coordonnées si et seulement si ce store en contient — et il rend impossible
/// l'état qui ferait mentir les CGU : un point présent sans consentement.
class ClientPositionStore {
  ClientPositionStore(this._prefs);

  static const _latKey = 'client_position_lat';
  static const _lngKey = 'client_position_lng';
  static const _consentKey = 'client_position_consent_version';

  final SharedPreferences _prefs;

  /// `null` = aucun point enregistré, donc **rien à transmettre**.
  ///
  /// ⚠️ Ne jamais y substituer un défaut : c'est le serveur qui applique le
  /// sien quand la requête n'en porte pas. Un défaut posé ici partirait sur le
  /// réseau comme s'il venait du client (règle #29).
  (double, double)? get() {
    final lat = _prefs.getDouble(_latKey);
    final lng = _prefs.getDouble(_lngKey);
    final version = _prefs.getString(_consentKey);
    if (lat == null || lng == null || version == null) return null;
    return (lat, lng);
  }

  /// Version du texte acceptée, ou `null`. Sert au re-consentement : une
  /// version différente de [kPositionConsentVersion] doit être redemandée.
  String? consentVersion() => _prefs.getString(_consentKey);

  Future<void> set(double latitude, double longitude) async {
    await _prefs.setDouble(_latKey, latitude);
    await _prefs.setDouble(_lngKey, longitude);
    await _prefs.setString(_consentKey, kPositionConsentVersion);
  }

  /// Retrait du consentement — **efface aussi le point**, sans quoi il
  /// resterait transmissible. « Un consentement qu'on ne peut pas reprendre
  /// n'en est pas un. »
  Future<void> clear() async {
    await _prefs.remove(_latKey);
    await _prefs.remove(_lngKey);
    await _prefs.remove(_consentKey);
  }
}
