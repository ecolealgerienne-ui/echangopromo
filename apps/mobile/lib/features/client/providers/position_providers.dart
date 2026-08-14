import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../data/local/client_position_store.dart';
import '../../../domain/models/client_geo_config.dart';
import '../../../providers/core_providers.dart';
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

/// Le point que le client a enregistré, ou `null`.
///
/// ⚠️ **`null` n'est pas « on ne sait pas », c'est « il n'a rien donné ».** La
/// distinction porte toute la porte de consentement : on n'émet des coordonnées
/// que si ce provider en a. Y mettre un défaut « en attendant » enverrait au
/// serveur une position au nom d'un client qui n'en a fourni aucune.
class ClientPositionController extends StateNotifier<(double, double)?> {
  ClientPositionController(this._store) : super(_store.get());

  final ClientPositionStore _store;

  /// Enregistre le point **et** le consentement — les deux ensemble, toujours.
  Future<void> enregistrer(double latitude, double longitude) async {
    await _store.set(latitude, longitude);
    state = (latitude, longitude);
  }

  /// Retire le consentement : le point est effacé avec lui, et l'app retombe
  /// sur le défaut serveur sans plus rien transmettre.
  Future<void> retirer() async {
    await _store.clear();
    state = null;
  }
}

final clientPositionProvider =
    StateNotifierProvider<ClientPositionController, (double, double)?>(
  (ref) => ClientPositionController(ref.watch(clientPositionStoreProvider)),
);

/// Où centrer une vue quand le client n'a rien enregistré.
///
/// Cascade à trois étages, **lue au même endroit par la liste et par la carte** :
/// le point enregistré, sinon celui du serveur, sinon le repli hors ligne.
final centreParDefautProvider = Provider<LatLng>((ref) {
  final enregistre = ref.watch(clientPositionProvider);
  if (enregistre != null) return LatLng(enregistre.$1, enregistre.$2);
  final config = ref.watch(clientGeoConfigProvider).valueOrNull;
  if (config != null) {
    return LatLng(config.defaultLatitude, config.defaultLongitude);
  }
  return kPointDeRepliHorsLigne;
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
