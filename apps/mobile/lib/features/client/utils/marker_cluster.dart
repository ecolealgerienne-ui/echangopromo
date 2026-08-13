import 'dart:math' as math;

import 'package:latlong2/latlong.dart';
import '../../../domain/models/map_shop.dart';

/// Un groupe de commerces trop proches à l'écran pour être distingués. Un
/// groupe d'un seul commerce s'affiche en point précis, les autres en rond
/// portant leur total.
class ShopCluster {
  const ShopCluster({required this.center, required this.shops});

  final LatLng center;
  final List<MapShop> shops;

  bool get isSingle => shops.length == 1;
  MapShop get single => shops.first;

  /// Nombre de **commerces** regroupés — ce que la grappe agrège réellement.
  int get count => shops.length;

  /// Nombre de **promos** portées par ces commerces.
  ///
  /// ⚠️ **C'est ce chiffre que la pastille affiche**, pas `count`. L'app sert à
  /// chercher des promos : le fil client, la vitrine et l'écran de détail
  /// comptent tous des promos, et la carte était la seule surface à compter des
  /// boutiques. Un client lisait « 24 » sur la carte et « 44 promos » dans la
  /// liste, pour exactement le même contenu — et en filtrant par catégorie il
  /// obtenait 4 + 22 = 26 d'un côté, 24 de l'autre, parce qu'un commerce dont
  /// les promos sont dans deux catégories compte dans les deux filtres et une
  /// seule fois dans « Toutes ». Les promos, elles, s'additionnent : 12 + 32 =
  /// 44 exactement.
  ///
  /// ⚠️ `count` reste, et sert toujours : c'est lui qui dit si la grappe peut
  /// se scinder, et la feuille ouverte au clic affiche les deux nombres pour
  /// que le lien entre la pastille et la liste des commerces reste lisible.
  int get promoCount =>
      shops.fold<int>(0, (total, shop) => total + shop.promos.length);
}

/// Regroupe les commerces par cellules de grille en **pixels d'écran**, pas
/// en degrés : deux commerces séparés de 100 m se chevauchent à faible zoom
/// et pas à fort zoom, donc le seuil de regroupement doit suivre le zoom.
/// C'est la projection Web Mercator utilisée par flutter_map, réappliquée
/// ici aux seules coordonnées.
///
/// Écrit à la main plutôt qu'ajouté en dépendance : les packages de
/// clustering pour flutter_map suivent avec retard ses versions majeures et
/// peuvent bloquer la résolution (règle d'audit #18), pour une logique qui
/// tient en quelques lignes.
List<ShopCluster> clusterShops(
  List<MapShop> shops, {
  required double zoom,
  double cellSizePx = 90,
}) {
  if (shops.isEmpty) return const [];

  // Taille du monde en pixels au zoom courant (tuiles de 256 px).
  final worldPx = 256 * math.pow(2, zoom).toDouble();
  final buckets = <String, List<MapShop>>{};

  for (final shop in shops) {
    final point = _project(shop.latitude, shop.longitude, worldPx);
    final cellX = (point.dx / cellSizePx).floor();
    final cellY = (point.dy / cellSizePx).floor();
    buckets.putIfAbsent('$cellX:$cellY', () => <MapShop>[]).add(shop);
  }

  return buckets.values.map((group) {
    // Centre du rond = barycentre du groupe, pour qu'il se pose au milieu
    // des commerces qu'il représente plutôt qu'au centre de la cellule.
    var latSum = 0.0;
    var lngSum = 0.0;
    for (final shop in group) {
      latSum += shop.latitude;
      lngSum += shop.longitude;
    }
    return ShopCluster(
      center: LatLng(latSum / group.length, lngSum / group.length),
      shops: group,
    );
  }).toList();
}

class _ProjectedPoint {
  const _ProjectedPoint(this.dx, this.dy);
  final double dx;
  final double dy;
}

/// Projection Web Mercator vers un plan carré de `worldPx` pixels de côté.
_ProjectedPoint _project(double lat, double lng, double worldPx) {
  // Mercator diverge aux pôles : borner évite un infini sur une donnée
  // aberrante (une latitude fausse ne doit pas faire planter la carte).
  final clampedLat = lat.clamp(-85.05112878, 85.05112878);
  final sinLat = math.sin(clampedLat * math.pi / 180);
  final x = (lng + 180) / 360 * worldPx;
  final y =
      (0.5 - math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi)) * worldPx;
  return _ProjectedPoint(x, y);
}
