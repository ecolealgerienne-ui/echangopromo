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

// ⚠️ **Un bloc de documentation ORPHELIN était ici, et il a survécu à son
// sujet.** Il décrivait `mapCenterForCommunesProvider`, supprimé lors de la
// bascule géographique du 2026-08-12 : le commentaire n'était rattaché à
// aucune déclaration, donc `analyze` ne le voyait pas et rien ne pouvait le
// signaler. Il a fallu une relecture adverse pour le trouver.
//
// Ce qu'il expliquait est repris ailleurs : le centre par défaut vient
// désormais du point que le client a enregistré, puis de `GET /promo/config`
// (voir `centreParDefautProvider`).

/// « Seulement mes favoris » **sur la carte** — un vrai filtre, celui-là.
///
/// ⚠️ **Volontairement distinct de `favoritesModeProvider`**, qui pilote la
/// liste. Là-bas, les favoris sont une **destination** : y entrer efface la
/// catégorie et la recherche, on en sort par « Accueil ». Ici, le cœur ne
/// remet rien à zéro et ne désigne aucun lieu — il retire des épingles, il se
/// combine avec la catégorie, et c'est tout. Deux natures derrière le même mot.
///
/// Le filtre catégorie, lui, **est** partagé entre les deux écrans : il est un
/// filtre des deux côtés. C'est ce qui rend le partage juste là-bas et faux
/// ici — la ressemblance des noms ne dit rien de la ressemblance des rôles.
final mapFavoritesOnlyProvider =
    StateProvider.autoDispose<bool>((ref) => false);

/// Les commerces portant **au moins une promo en favori**.
///
/// ⚠️ **C'est une traduction, pas un filtre évident** : un favori est une
/// *promo*, la carte affiche des *commerces*. Le sens retenu — « ce commerce
/// m'intéresse dès qu'une de ses promos m'intéresse » — a une conséquence
/// assumée : une épingle apparaît pour un commerce dont une seule promo sur
/// dix est en favori.
///
/// Fonction libre plutôt que méthode ou provider : elle est pure, donc
/// éprouvable sans carte, sans réseau et sans widget.
List<MapShop> commercesAvecFavori(List<MapShop> shops, Set<String> favoris) =>
    shops
        .where((shop) => shop.promos.any((promo) => favoris.contains(promo.id)))
        .toList();

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
