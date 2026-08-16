import 'package:echango_promo/domain/enums/categorie.dart';
import 'package:echango_promo/domain/enums/promo_lifecycle_status.dart';
import 'package:echango_promo/domain/enums/promo_moderation_status.dart';
import 'package:echango_promo/domain/models/map_shop.dart';
import 'package:echango_promo/domain/models/promo.dart';
import 'package:echango_promo/features/client/providers/map_providers.dart';
import 'package:flutter_test/flutter_test.dart';

/// ⚠️ **Le filtre favoris de la carte est une TRADUCTION, pas une égalité.**
/// Un favori est une *promo* ; la carte affiche des *commerces*. C'est cette
/// traduction — « ce commerce m'intéresse dès qu'une de ses promos
/// m'intéresse » — que ce banc éprouve, y compris dans ce qu'elle refuse.
Promo _promo(String id) => Promo(
      id: id,
      commercantId: 'c',
      description: 'promo $id',
      prixAvant: 100,
      prixApres: 60,
      categorie: Categorie.values.first,
      dateFin: null,
      lifecycleStatus: PromoLifecycleStatus.publiee,
      moderationStatus: PromoModerationStatus.normale,
      photoUrls: const [],
      createdAt: DateTime(2026, 8, 16),
    );

MapShop _commerce(String id, List<String> promoIds) => MapShop(
      id: id,
      nom: 'Commerce $id',
      categorie: Categorie.values.first,
      latitude: 34.67,
      longitude: 3.26,
      promos: promoIds.map(_promo).toList(),
    );

void main() {
  final parc = [
    _commerce('a', ['p1', 'p2']),
    _commerce('b', ['p3']),
    _commerce('c', []),
  ];

  group('commercesAvecFavori', () {
    test('le témoin : sans filtre, le parc n\'est pas vide', () {
      // ⚠️ Sans lui, un parc vide ferait passer TOUS les cas de refus
      // ci-dessous : le silence est aussi ce que rend une mesure qui ne
      // mesure rien (règle #28).
      expect(parc, hasLength(3));
    });

    test('un commerce est retenu dès QU\'UNE de ses promos est en favori', () {
      final retenus = commercesAvecFavori(parc, {'p2'});
      expect(retenus.map((s) => s.id), ['a']);
    });

    test('aucun favori posé ne retient AUCUN commerce', () {
      // Et surtout pas « tous » : un ensemble vide qui ne filtre rien est le
      // repli qui rendrait le bouton sans effet apparent (règle #29).
      expect(commercesAvecFavori(parc, const {}), isEmpty);
    });

    test('un favori inconnu du parc ne retient rien', () {
      expect(commercesAvecFavori(parc, {'p-ailleurs'}), isEmpty);
    });

    test('un commerce sans aucune promo n\'est jamais retenu', () {
      final retenus = commercesAvecFavori(parc, {'p1', 'p3'});
      expect(retenus.map((s) => s.id), ['a', 'b']);
      expect(retenus.map((s) => s.id), isNot(contains('c')));
    });

    test('l\'ordre du serveur est conservé', () {
      // La carte n'a pas d'ordre à l'écran, mais le sélecteur de groupe, si :
      // réordonner ici ferait diverger deux listes sans raison.
      final retenus = commercesAvecFavori(parc, {'p3', 'p1'});
      expect(retenus.map((s) => s.id), ['a', 'b']);
    });
  });
}
