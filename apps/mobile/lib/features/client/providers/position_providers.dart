import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../data/local/client_position_store.dart';
import '../../../domain/models/client_geo_config.dart';
import '../../../providers/core_providers.dart';
import 'location_providers.dart';
import 'map_providers.dart';
import 'promo_providers.dart';

/// **L'unique coordonnée écrite en dur dans l'app.**
///
/// Elle ne sert qu'au tout premier lancement hors ligne, avant que
/// `GET /promo/config` ait répondu une première fois. Partout ailleurs, le
/// point par défaut vient du serveur — c'est ce qui permet de le changer sans
/// republier sur les stores.
///
/// ⚠️ **Un seul exemplaire, délibérément.** `map_screen.dart` en portait un
/// autre (Djelfa), pendant que la configuration serveur en annonçait un
/// différent : un client sans point enregistré aurait vu une liste autour de
/// l'un et une carte autour de l'autre. Deux valeurs de repli finissent
/// toujours par diverger (A4 du plan de bascule).
///
/// ⚠️ Ne jamais la lire dans un vérificateur : `check_server_rules.dart`
/// capture `(\d+)` et fait `int.parse`, donc lirait `34` pour `34.6703` **en
/// rendant vert**.
const kPointDeRepliHorsLigne = LatLng(34.6703, 3.2630);

final clientPositionStoreProvider = Provider(
    (ref) => ClientPositionStore(ref.watch(sharedPreferencesProvider)));

/// Repères servis par le serveur. Tant qu'ils n'ont pas répondu, l'app se rabat
/// sur [kPointDeRepliHorsLigne] et n'envoie aucun rayon (le serveur applique
/// alors le sien).
final clientGeoConfigProvider = FutureProvider<ClientGeoConfig>(
    (ref) => ref.watch(promoApiProvider).clientConfig());

/// Le cadre de recherche du client : **un point et la largeur qu'il a cadrée**.
///
/// ⚠️ Le rayon est né le 2026-08-14 d'une remarque de terrain : depuis Alger,
/// zoomer sur un quartier puis revenir à la liste montrait tout Alger. Le geste
/// « Chercher autour de ce point » prenait le centre de la carte et **jetait le
/// zoom**, en lui collant le rayon par défaut du serveur. Le point était donc
/// juste et le cadrage faux, ce qui est le plus difficile à voir : la liste a
/// l'air de marcher.
///
/// ⚠️ `rayonKm` reste **nullable**, et ce n'est pas un oubli. Un client qui n'a
/// jamais posé de point, ou qui l'a posé avant cette version, n'a pas de
/// cadrage : le serveur applique alors le sien. Y mettre une valeur par défaut
/// ici rendrait ces deux cas indiscernables (règle 29).
class PointDeRecherche {
  const PointDeRecherche({
    required this.latitude,
    required this.longitude,
    this.rayonKm,
  });

  /// Recompose l'état au démarrage depuis le stockage. Le rayon est ignoré si
  /// le point est absent — un cadrage orphelin n'a rien à cadrer.
  static PointDeRecherche? depuis((double, double)? point, double? rayonKm) =>
      point == null
          ? null
          : PointDeRecherche(
              latitude: point.$1, longitude: point.$2, rayonKm: rayonKm);

  final double latitude;
  final double longitude;
  final double? rayonKm;

  /// Ce qui part sur le réseau, et rien d'autre.
  (double, double) get coordonnees => (latitude, longitude);
}

/// Le point que le client a enregistré, ou `null`.
///
/// ⚠️ **`null` n'est pas « on ne sait pas », c'est « il n'a rien donné ».** La
/// distinction porte toute la porte de consentement : on n'émet des coordonnées
/// que si ce provider en a. Y mettre un défaut « en attendant » enverrait au
/// serveur une position au nom d'un client qui n'en a fourni aucune.
class ClientPositionController extends StateNotifier<PointDeRecherche?> {
  ClientPositionController(this._store)
      : super(PointDeRecherche.depuis(_store.get(), _store.rayonKm()));

  final ClientPositionStore _store;

  /// Enregistre le point **et** le consentement — les deux ensemble, toujours.
  ///
  /// `rayonKm` vient du zoom de la carte au moment du geste (voir
  /// `rayonDepuisLaVue` dans `map_screen.dart`). Absent, le serveur applique le
  /// sien : c'est une absence, pas un défaut posé ici.
  Future<void> enregistrer(double latitude, double longitude,
      {double? rayonKm}) async {
    await _store.set(latitude, longitude, rayonKm: rayonKm);
    state = PointDeRecherche(
        latitude: latitude, longitude: longitude, rayonKm: rayonKm);
  }

  /// Retire le consentement : le point est effacé avec lui, et l'app retombe
  /// sur le défaut serveur sans plus rien transmettre.
  Future<void> retirer() async {
    await _store.clear();
    state = null;
  }
}

final clientPositionProvider =
    StateNotifierProvider<ClientPositionController, PointDeRecherche?>(
  (ref) => ClientPositionController(ref.watch(clientPositionStoreProvider)),
);

/// Où centrer une vue quand le client n'a rien enregistré.
///
/// Cascade à trois étages, **lue au même endroit par la liste et par la carte** :
/// le point enregistré, sinon celui du serveur, sinon le repli hors ligne.
final centreParDefautProvider = Provider<LatLng>((ref) {
  final enregistre = ref.watch(clientPositionProvider);
  if (enregistre != null) {
    return LatLng(enregistre.latitude, enregistre.longitude);
  }
  final config = ref.watch(clientGeoConfigProvider).valueOrNull;
  if (config != null) {
    return LatLng(config.defaultLatitude, config.defaultLongitude);
  }
  return kPointDeRepliHorsLigne;
});

/// Point depuis lequel une distance peut être **affichée et triée**, ou `null`.
///
/// Trois différences avec [centreParDefautProvider], toutes voulues :
///
/// 1. **Le GPS d'abord** : « à 800 m » veut dire « de là où je suis », c'est le
///    repère qu'attend quelqu'un qui lit une distance. Il reste sur l'appareil
///    et n'est jamais transmis (voir `PromoApi.listActive`).
/// 2. **Sinon le point de recherche** — celui que le client a enregistré, sinon
///    celui du serveur. C'est autour de lui que la liste est construite, donc
///    une distance calculée depuis lui est cohérente avec ce que l'écran
///    annonce (« Autour du point par défaut »).
/// 3. ⚠️ **Jamais [kPointDeRepliHorsLigne].** Cadrer une carte sur un repli est
///    sans conséquence : on voit qu'on est ailleurs. Afficher « 231 km »
///    calculés depuis un point arbitraire est un chiffre **faux présenté comme
///    mesuré**, que rien à l'écran ne dénonce (règle 29). L'absence rend `null`,
///    la carte n'affiche alors pas de distance et le tri par proximité laisse
///    l'ordre du serveur.
///
/// ⚠️ **Ne jamais s'en servir pour bâtir une requête.** La porte de
/// consentement est [clientPositionProvider], et elle seule : ce provider-ci
/// mélange une lecture de capteur et un défaut serveur, et l'émettre reviendrait
/// à transmettre une position au nom d'un client qui n'en a donné aucune.
final pointDeReferenceProvider = Provider.autoDispose<LatLng?>((ref) {
  final gps = ref.watch(userPositionProvider).valueOrNull;
  if (gps != null) return gps;
  final enregistre = ref.watch(clientPositionProvider);
  if (enregistre != null) {
    return LatLng(enregistre.latitude, enregistre.longitude);
  }
  final config = ref.watch(clientGeoConfigProvider).valueOrNull;
  if (config != null) {
    return LatLng(config.defaultLatitude, config.defaultLongitude);
  }
  return null;
});

/// Tout ce qui dépend du point de recherche, invalidé **par une fonction
/// nommée**.
///
/// ⚠️ Jamais une liste d'`invalidate` recopiée dans chaque écran : c'est celui
/// qu'on oublie qui affiche un résultat périmé, sans erreur ni journal
/// (règle #37). Le seul équivalent existant est `invalidateAfterPromoChange`.
///
/// ⚠️ Et aucun test hors appareil ne voit ce défaut : il faut un parcours qui
/// **revienne** sur la liste après avoir changé le point.
void invalidateAfterPositionChange(WidgetRef ref) {
  ref.invalidate(topPromosProvider);
  ref.invalidate(mapShopsProvider);
}
