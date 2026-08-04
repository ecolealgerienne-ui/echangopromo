import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/models/map_shop.dart';
import '../../../providers/core_providers.dart';
import 'promo_providers.dart';

/// Zone visible de la carte, mise à jour à la fin de chaque déplacement.
class MapBounds {
  const MapBounds({
    required this.north,
    required this.south,
    required this.east,
    required this.west,
  });

  final double north;
  final double south;
  final double east;
  final double west;

  /// Zone élargie autour de la zone visible. On charge volontairement plus
  /// large que l'écran pour qu'un déplacement modéré reste servi par les
  /// données déjà en main, au lieu de relancer une requête — et de faire
  /// clignoter les points — au moindre glissement du doigt.
  MapBounds padded([double factor = 0.6]) {
    final latMargin = (north - south) * factor / 2;
    final lngMargin = (east - west) * factor / 2;
    return MapBounds(
      north: (north + latMargin).clamp(-90.0, 90.0).toDouble(),
      south: (south - latMargin).clamp(-90.0, 90.0).toDouble(),
      east: (east + lngMargin).clamp(-180.0, 180.0).toDouble(),
      west: (west - lngMargin).clamp(-180.0, 180.0).toDouble(),
    );
  }

  /// `true` si [other] tient entièrement dans cette zone — donc si les
  /// commerces déjà chargés couvrent ce que l'utilisateur regarde.
  bool contains(MapBounds other) =>
      other.north <= north &&
      other.south >= south &&
      other.east <= east &&
      other.west >= west;

  @override
  bool operator ==(Object other) =>
      other is MapBounds &&
      other.north == north &&
      other.south == south &&
      other.east == east &&
      other.west == west;

  @override
  int get hashCode => Object.hash(north, south, east, west);
}

/// Commerces de la zone visible. `autoDispose` + `family` : chaque zone est
/// une requête distincte, et le cache se libère en quittant l'écran plutôt
/// que de garder en mémoire toutes les zones déjà survolées.
final mapShopsProvider = FutureProvider.autoDispose
    .family<MapShopsResult, MapBounds>((ref, bounds) async {
  final categorie = ref.watch(categoryFilterProvider);
  return ref.watch(promoApiProvider).listForMap(
        north: bounds.north,
        south: bounds.south,
        east: bounds.east,
        west: bounds.west,
        categorie: categorie,
      );
});
