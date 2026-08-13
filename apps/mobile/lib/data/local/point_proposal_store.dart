import 'package:shared_preferences/shared_preferences.dart';

/// Mémorise que l'utilisateur a écarté la proposition d'enregistrer une ville
/// par défaut, affichée sur la carte.
///
/// ── Pourquoi un drapeau SÉPARÉ de `LocationInviteStore` ─────────────────────
///
/// Les deux bandeaux se ressemblent et ne disent pas la même chose :
/// l'invitation demande d'**activer la localisation**, la proposition demande
/// d'**enregistrer une ville**. Écarter l'une n'est pas écarter l'autre — un
/// client peut très bien refuser le GPS et vouloir choisir sa ville à la main,
/// ou l'inverse. Partager la clé ferait disparaître une proposition que
/// personne n'a écartée.
///
/// ── ⚠️ Deux drapeaux, parce qu'il y a deux moments ──────────────────────────
///
/// La proposition survient dans deux situations que le client vit
/// différemment, et les confondre ferait taire la seconde pour toujours :
///
/// - **le premier positionnement** — le client n'a aucune ville enregistrée et
///   le GPS vient de le placer. Écarter ici veut dire « je ne veux pas
///   enregistrer ma position », une fois pour toutes ;
/// - **le changement de ville** — le client a déjà une ville et il en explore
///   une autre, loin. Écarter ici veut dire « pas cette fois ».
///
/// Le second se réarme donc à chaque nouvelle ville : c'est une proposition
/// contextuelle, pas une sollicitation. Le premier, lui, ne revient pas — même
/// raison que l'invitation à la localisation, refusée par Apple le 2026-08-05
/// au titre de la règle 5.1.1(iv) : *une proposition faite au bon moment est
/// légitime ; la même proposition répétée ne l'est plus.*
class PointProposalStore {
  PointProposalStore(this._prefs);

  static const _clePremierPoint = 'point_proposal_first_dismissed';
  static const _cleVilleEcartee = 'point_proposal_area_dismissed';

  final SharedPreferences _prefs;

  /// Le client a écarté la proposition d'enregistrer sa **première** ville.
  bool premierPointEcarte() => _prefs.getBool(_clePremierPoint) ?? false;

  Future<void> ecarterPremierPoint() => _prefs.setBool(_clePremierPoint, true);

  /// La ville écartée en explorant, arrondie au centième de degré (~1 km).
  ///
  /// ⚠️ **Arrondie, et c'est le cœur du mécanisme.** Mémoriser des coordonnées
  /// exactes ne servirait à rien : le centre de la carte bouge d'un pixel au
  /// moindre geste, donc la proposition reviendrait aussitôt. Mémoriser la
  /// ville entière la ferait taire trop largement. Le centième de degré est la
  /// maille à laquelle « c'est la même ville » devient vrai.
  String? villeEcartee() => _prefs.getString(_cleVilleEcartee);

  Future<void> ecarterVille(double latitude, double longitude) =>
      _prefs.setString(_cleVilleEcartee, cleDeVille(latitude, longitude));

  /// ⚠️ Exposée pour que l'appelant compare **la même chose** que ce qui a été
  /// mémorisé. Deux arrondis écrits à deux endroits, c'est un invariant qui
  /// tient sur un commentaire (règle 30).
  static String cleDeVille(double latitude, double longitude) =>
      '${latitude.toStringAsFixed(2)},${longitude.toStringAsFixed(2)}';
}
