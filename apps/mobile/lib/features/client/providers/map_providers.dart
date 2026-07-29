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
final mapShopsProvider =
    FutureProvider.autoDispose.family<MapShopsResult, MapBounds>((ref, bounds) async {
  final categorie = ref.watch(categoryFilterProvider);
  return ref.watch(promoApiProvider).listForMap(
        north: bounds.north,
        south: bounds.south,
        east: bounds.east,
        west: bounds.west,
        categorie: categorie,
      );
});
