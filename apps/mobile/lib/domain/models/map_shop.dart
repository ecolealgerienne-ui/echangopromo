import '../enums/categorie.dart';
import 'promo.dart';

/// Commerçant géolocalisé affiché sur la carte, avec ses promos actives
/// (`GET /promo/map`). Les positions sont garanties non nulles par le
/// backend : la requête écarte les commerçants sans coordonnées.
class MapShop {
  const MapShop({
    required this.id,
    required this.nom,
    required this.categorie,
    this.adresse,
    this.telephone,
    required this.latitude,
    required this.longitude,
    this.photoUrl,
    required this.promos,
  });

  factory MapShop.fromJson(Map<String, dynamic> json) => MapShop(
        id: json['id'] as String,
        nom: json['nom'] as String,
        categorie: Categorie.fromValue(json['categorie'] as String),
        adresse: json['adresse'] as String?,
        telephone: json['telephone'] as String?,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        photoUrl: json['photoUrl'] as String?,
        promos: (json['promos'] as List<dynamic>? ?? const [])
            .map((e) => Promo.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final String id;
  final String nom;
  final Categorie categorie;
  final String? adresse;
  final String? telephone;
  final double latitude;
  final double longitude;
  final String? photoUrl;
  final List<Promo> promos;

  /// Réduction la plus forte du commerce, affichée sur son point de carte :
  /// c'est l'information qui décide de cliquer, plus qu'un pictogramme muet.
  /// `null` si aucune promo n'a de prix exploitable.
  int? get bestDiscountPercent {
    int? best;
    for (final promo in promos) {
      if (promo.prixAvant <= 0 || promo.prixApres >= promo.prixAvant) continue;
      final percent =
          (((promo.prixAvant - promo.prixApres) / promo.prixAvant) * 100)
              .round();
      if (best == null || percent > best) best = percent;
    }
    return best;
  }
}

/// Réponse de `GET /promo/map`. `truncated` signale que la zone contient
/// plus de commerces que le plafond serveur — l'app invite alors à zoomer
/// plutôt que d'afficher une carte silencieusement incomplète.
class MapShopsResult {
  const MapShopsResult({required this.items, required this.truncated});

  factory MapShopsResult.fromJson(Map<String, dynamic> json) => MapShopsResult(
        items: (json['items'] as List<dynamic>)
            .map((e) => MapShop.fromJson(e as Map<String, dynamic>))
            .toList(),
        truncated: json['truncated'] as bool? ?? false,
      );

  final List<MapShop> items;
  final bool truncated;
}
