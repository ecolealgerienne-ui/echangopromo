import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Position de l'utilisateur, ou `null` si elle n'est pas disponible
/// (localisation refusée, service désactivé, matériel qui ne répond pas).
///
/// Ne **demande jamais** la permission : la demander depuis un provider de
/// lecture ferait surgir une boîte système au milieu de la carte, sans que
/// l'utilisateur ait rien touché — et brûlerait la permission en cas de refus.
/// La demande part de deux gestes explicites, et de ceux-là seulement :
/// l'onboarding (`onboarding_navigation.dart`) et le bouton « me localiser »
/// de la carte, qui passent tous deux par
/// [demanderPermissionLocalisation].
///
/// Toute erreur retombe sur `null` plutôt que de remonter : la carte et les
/// fiches doivent fonctionner sans position, seule la distance disparaît.
final userPositionProvider = FutureProvider<LatLng?>((ref) async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;

    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      return null;
    }

    // Dernière position connue d'abord : elle est instantanée (déjà en cache
    // système) là où un nouveau relevé demande un verrou GPS. Retour terrain
    // 2026-07-30 : la carte restait plusieurs dizaines de secondes sur le
    // centre de repli avant de se recentrer.
    final cached = await Geolocator.getLastKnownPosition();
    if (cached != null && _isFreshEnough(cached)) {
      return LatLng(cached.latitude, cached.longitude);
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        // `medium` (~100-500 m) et non `high` : la position ne sert qu'à
        // centrer la carte et afficher une distance approximative ("à
        // 300 m"). `high` force un verrou GPS satellite qui peut prendre
        // plus de 30 s en intérieur — précision inutile ici, payée très
        // cher en attente et en batterie.
        accuracy: LocationAccuracy.medium,
        // Sans limite, l'attente est potentiellement infinie sur un
        // appareil qui ne capte pas.
        timeLimit: Duration(seconds: 12),
      ),
    );
    return LatLng(position.latitude, position.longitude);
  } catch (_) {
    // Relevé impossible ou expiré : une position même ancienne vaut mieux
    // que pas de position du tout (carte centrée sur le repli, distances
    // absentes). `null` seulement si l'appareil n'en a jamais eu.
    try {
      final stale = await Geolocator.getLastKnownPosition();
      return stale == null ? null : LatLng(stale.latitude, stale.longitude);
    } catch (_) {
      return null;
    }
  }
});

/// Une position vieille de quelques minutes reste bonne à l'échelle d'une
/// ville : au-delà, on préfère un relevé neuf.
bool _isFreshEnough(Position position) =>
    DateTime.now().difference(position.timestamp) < const Duration(minutes: 10);

/// Distance à vol d'oiseau en mètres, ou `null` si l'un des deux points
/// manque. Calculée sur l'appareil : le backend n'a pas besoin de connaître
/// la position du client pour un simple affichage.
double? distanceTo(LatLng? from, double? latitude, double? longitude) {
  if (from == null || latitude == null || longitude == null) return null;
  return Geolocator.distanceBetween(
      from.latitude, from.longitude, latitude, longitude);
}

/// Ce qu'un geste « me localiser » a produit — trois issues, trois remèdes
/// **différents**.
///
/// ⚠️ **Un booléen ne suffisait pas, et c'est ce qui a fabriqué une impasse.**
/// `demanderPermissionLocalisation` rendait `true`/`false` : « pas accordée »
/// couvrait alors trois situations qui n'ont pas du tout la même sortie —
/// redemander, activer le service, ou passer par les réglages du système. Sans
/// les distinguer, l'app ne pouvait proposer que la première, celle qui ne
/// marche justement plus une fois le refus posé.
enum LocationOutcome {
  /// Accordée — `userPositionProvider` va pouvoir rendre une position.
  granted,

  /// Le service de localisation de l'appareil est coupé : aucune permission
  /// n'y changerait quoi que ce soit, c'est un réglage système.
  serviceOff,

  /// Refusée, et plus rien à demander.
  ///
  /// ⚠️ **Sur iOS, c'est l'état dès le premier « Ne pas autoriser ».** Le
  /// plugin traduit `notDetermined` en `denied` et le vrai refus utilisateur
  /// en `deniedForever` : `requestPermission()` ne rouvre alors plus jamais de
  /// boîte. La seule sortie est l'app Réglages — ce qu'Apple nomme lui-même
  /// dans sa réponse du 2026-08-07 (*« provide a link to the Settings app »*).
  denied,
}

/// Demande la position **au moment où l'utilisateur touche la fonction**.
///
/// L'état est relu à chaque appel plutôt que mémorisé : l'utilisateur peut
/// être allé changer le réglage dans le système et être revenu, et un état
/// gardé en cache lui répondrait alors avec l'ancien monde.
Future<LocationOutcome> demanderPermissionLocalisation() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    return LocationOutcome.serviceOff;
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  return permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always
      ? LocationOutcome.granted
      : LocationOutcome.denied;
}

/// Ouvre la fiche de l'app dans les réglages du système — la seule porte qui
/// reste après un refus. Enveloppées ici, et pas appelées directement depuis
/// un écran : `geolocator` ne franchit pas la frontière des providers.
Future<void> ouvrirReglagesApplication() async {
  await Geolocator.openAppSettings();
}

/// Ouvre les réglages de localisation de l'appareil (service coupé).
Future<void> ouvrirReglagesLocalisation() async {
  await Geolocator.openLocationSettings();
}
