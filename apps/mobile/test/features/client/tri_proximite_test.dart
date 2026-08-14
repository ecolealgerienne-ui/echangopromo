import 'package:echango_promo/domain/models/promo.dart';
import 'package:echango_promo/features/client/providers/promo_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// Le défaut réparé le 2026-08-14 : le tri local par `nouveautes` écrasait
/// l'ordre par distance rendu par le serveur. Mesuré sur le décor,
/// `search=promo` : 65 résultats de 0,1 km à 245 km, strictement ordonnés par
/// distance côté serveur — et une promo à 231,7 km affichée en 5ᵉ position,
/// devant des dizaines à 100 mètres.
///
/// ⚠️ Deux choses distinctes sont éprouvées ici, et la première compte autant
/// que la seconde : **la valeur par défaut** (c'est elle qui portait le
/// défaut, silencieusement) et **le tri lui-même**.
Promo _promo(String id, double? lat, double? lng) => Promo.fromJson({
      'id': id,
      'commercantId': 'c-$id',
      'description': 'Promo $id',
      'prixAvant': 100,
      'prixApres': 80,
      'categorie': 'autre',
      'dateFin': null,
      'lifecycleStatus': 'publiee',
      'moderationStatus': 'normale',
      'photoUrl': null,
      'createdAt': DateTime(2026, 7, 1).toIso8601String(),
      'commercantLatitude': lat,
      'commercantLongitude': lng,
    });

// Djelfa, le point par défaut servi par `GET /promo/config`.
const _djelfa = LatLng(34.6703, 3.2630);

void main() {
  group('valeur par défaut du tri', () {
    test('vaut proximite — et surtout pas nouveautes', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // ⚠️ C'est LE contrôle de non-régression du défaut. `nouveautes`
      // ressemblait à un choix d'affichage anodin ; c'était en réalité
      // l'annulation systématique de l'ordre géographique du serveur, sur
      // toutes les listes et pas seulement la recherche.
      expect(container.read(promoSortProvider), PromoSort.proximite);
    });
  });

  group('trierParProximite', () {
    test('le plus proche passe devant le plus loin', () {
      // Alger est à ~230 km de Djelfa, le commerce voisin à quelques centaines
      // de mètres. C'est le cas réel qui a fait remonter le défaut.
      final loin = _promo('alger', 36.7538, 3.0588);
      final pres = _promo('voisin', 34.6750, 3.2650);
      final promos = [loin, pres];

      trierParProximite(promos, _djelfa);

      expect(promos.map((p) => p.id), ['voisin', 'alger']);
    });

    test('sans repère, l\'ordre reçu du serveur est laissé intact', () {
      // ⚠️ Ne rien faire est ici la bonne réponse : le serveur a déjà ordonné
      // par distance autour du point de recherche. Un tri fabriqué depuis un
      // point inventé serait pire que pas de tri (règle 29).
      final promos = [
        _promo('alger', 36.7538, 3.0588),
        _promo('voisin', 34.6750, 3.2650),
      ];

      trierParProximite(promos, null);

      expect(promos.map((p) => p.id), ['alger', 'voisin']);
    });

    test('une promo sans coordonnées va à la fin, jamais en tête', () {
      // Le piège que ce cas interdit : traiter une position absente comme
      // « distance 0 » — ce que ferait le moindre `?? 0` — placerait cette
      // promo devant le commerce d'en face.
      final promos = [
        _promo('sans-position', null, null),
        _promo('alger', 36.7538, 3.0588),
        _promo('voisin', 34.6750, 3.2650),
      ];

      trierParProximite(promos, _djelfa);

      expect(promos.map((p) => p.id), ['voisin', 'alger', 'sans-position']);
    });

    test('deux promos sans coordonnées ne se départagent pas arbitrairement',
        () {
      final promos = [
        _promo('sans-a', null, null),
        _promo('sans-b', null, null),
        _promo('voisin', 34.6750, 3.2650),
      ];

      trierParProximite(promos, _djelfa);

      expect(promos.first.id, 'voisin');
      expect(
          promos.skip(1).map((p) => p.id), containsAll(['sans-a', 'sans-b']));
    });
  });
}
