import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Position de l'utilisateur, ou `null` si elle n'est pas disponible
/// (localisation refusée, service désactivé, matériel qui ne répond pas).
///
/// Ne **demande jamais** la permission : c'est le rôle de l'onboarding
/// (`onboarding_navigation.dart`), qui l'expose au bon moment avec une
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

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return LatLng(position.latitude, position.longitude);
  } catch (_) {
    return null;
  }
});

/// Distance à vol d'oiseau en mètres, ou `null` si l'un des deux points
/// manque. Calculée sur l'appareil : le backend n'a pas besoin de connaître
/// la position du client pour un simple affichage.
double? distanceTo(LatLng? from, double? latitude, double? longitude) {
  if (from == null || latitude == null || longitude == null) return null;
  return Geolocator.distanceBetween(from.latitude, from.longitude, latitude, longitude);
}
