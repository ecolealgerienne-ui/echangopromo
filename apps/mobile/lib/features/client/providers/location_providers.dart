import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Position de l'utilisateur, ou `null` si elle n'est pas disponible
/// (localisation refusée, service désactivé, matériel qui ne répond pas).
///
/// Ne **demande jamais** la permission : c'est le rôle de l'onboarding
/// (l'invitation contextuelle de la carte), qui l'expose au bon moment avec une
/// explication. La redemander ici ferait surgir une boîte système au milieu
/// de la carte, sans contexte, et brûlerait la permission en cas de refus.
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

/// Vrai quand la localisation peut encore être **demandée** — service activé
/// et permission simplement `denied`.
///
/// ⚠️ `deniedForever` rend `false` **exprès** : à ce stade, `requestPermission`
/// ne fait plus rien. Proposer un bouton qui n'a aucun effet, c'est le même
/// défaut que la carte évite déjà pour « me localiser » — *« un bouton présent
/// mais inerte laisse croire à une panne »*. Mieux vaut ne rien montrer.
final peutDemanderLocalisationProvider = FutureProvider<bool>((ref) async {
  if (!await Geolocator.isLocationServiceEnabled()) return false;
  return await Geolocator.checkPermission() == LocationPermission.denied;
});

/// Demande la permission et rend `true` si elle est accordée.
///
/// Sans navigation : contrairement à l'onboarding, l'appelant est déjà sur
/// l'écran qui en a besoin et n'a nulle part où aller.
Future<bool> demanderPermissionLocalisation() async {
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  return permission == LocationPermission.whileInUse ||
      permission == LocationPermission.always;
}
