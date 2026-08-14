import 'package:echango_promo/features/client/providers/position_providers.dart';
import 'package:echango_promo/features/client/screens/map_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// Le geste « Chercher autour de ce point » prenait le centre de la carte et
/// **jetait le zoom** : cadrer une rue ou une wilaya donnait la même liste, au
/// rayon par défaut du serveur. Remarqué depuis Alger le 2026-08-14 — zoomer
/// sur un quartier puis revenir à la liste montrait tout Alger.
///
/// ⚠️ Le point était juste et la largeur fausse, ce qui est le plus difficile à
/// voir : la liste a l'air de marcher.
const _plafond = 50.0;

// Un rectangle de ~3,5 km de diagonale autour de Djelfa.
final _nordOuestQuartier = LatLng(34.68, 3.25);
final _sudEstQuartier = LatLng(34.66, 3.28);

void main() {
  group('rayonDepuisLaVue', () {
    test('une vue ordinaire donne la demi-diagonale', () {
      final r = rayonDepuisLaVue(_nordOuestQuartier, _sudEstQuartier,
          plafondKm: _plafond);
      // Cercle circonscrit au rectangle visible : il couvre tout l'écran et un
      // peu au-delà. Le cercle inscrit laisserait les coins de la carte hors de
      // la liste — on verrait des commerces qu'on ne retrouverait pas.
      expect(r, isNotNull);
      expect(r!, greaterThan(1.0));
      expect(r, lessThan(3.0));
    });

    test('une vue très serrée ne descend pas sous le plancher', () {
      // ⚠️ Sans plancher, zoomer à fond donnerait un rayon de quelques dizaines
      // de mètres — une précision que ni le point du client ni le cercle
      // circonscrit n'ont.
      final r = rayonDepuisLaVue(
          LatLng(34.6700, 3.2600), LatLng(34.6699, 3.2601),
          plafondKm: _plafond);
      expect(r, 1.0);
    });

    test('une vue très large est plafonnée par le serveur', () {
      // Le plafond vient de `GET /promo/config`, jamais d'une constante
      // recopiée dans l'app (règle 32).
      final r = rayonDepuisLaVue(LatLng(38.0, 0.0), LatLng(28.0, 10.0),
          plafondKm: _plafond);
      expect(r, _plafond);
    });

    test('sans plafond serveur, rend null — et surtout pas une valeur', () {
      // ⚠️ Transmettre un rayon non borné vaut moins que ne rien transmettre :
      // le serveur applique alors le sien. Une valeur de repli ici rendrait
      // « je n'ai pas pu borner » indiscernable de « le client a cadré ça »
      // (règle 29).
      final r = rayonDepuisLaVue(_nordOuestQuartier, _sudEstQuartier,
          plafondKm: null);
      expect(r, isNull);
    });
  });

  group('rayonBorne — la borne produit', () {
    // ⚠️ echango Promo sert des promos de proximité, pas des annonces
    // nationales (décision du 2026-08-14). Dézoomer sur toute la wilaya montre
    // plus de carte, pas plus de liste.
    test('un cadrage plus large que le plafond est ramené au plafond', () {
      expect(rayonBorne(40.0, 5.0), 5.0);
    });

    test('un cadrage plus serré est conservé tel quel', () {
      // La borne est un plafond, pas une valeur imposée : chercher dans son
      // quartier reste possible.
      expect(rayonBorne(1.5, 5.0), 1.5);
      expect(rayonBorne(5.0, 5.0), 5.0);
    });

    test('rien à borner reste une absence', () {
      // ⚠️ `null` veut dire « le client n'a rien cadré » : y substituer le
      // plafond enverrait un rayon en son nom (règle 29).
      expect(rayonBorne(null, 5.0), isNull);
    });

    test('sans plafond connu, on ne rabote pas en douce', () {
      // La config serveur n'a pas encore répondu : on transmet ce que le client
      // a cadré plutôt qu'un chiffre inventé.
      expect(rayonBorne(12.0, null), 12.0);
    });

    test('un rayon large déjà stocké est borné à l\'émission', () {
      // ⚠️ Le cas qui rend cette fonction nécessaire ailleurs qu'au moment du
      // geste : un client ayant cadré 40 km avant cette version. Une borne
      // posée seulement à l'enregistrement ne l'aurait jamais rattrapé.
      expect(rayonBorne(40.0, 5.0), lessThanOrEqualTo(5.0));
    });
  });

  group('cadreDepuisLeRayon', () {
    test('aller-retour : la vue redonne le rayon dont elle vient', () {
      // ⚠️ **C'est l'invariant qui tient la carte et la liste ensemble.** Le
      // zoom n'est pas stocké — il serait une seconde valeur disant la même
      // chose que le rayon, et deux valeurs qui doivent s'accorder finissent
      // par diverger. Il est donc reconstruit, et ce test est ce qui garantit
      // que la reconstruction rend bien le cadre d'origine.
      const centre = LatLng(34.6703, 3.2630);
      for (final rayon in [1.0, 4.0, 12.5, 50.0]) {
        final cadre = cadreDepuisLeRayon(centre, rayon);
        expect(cadre, isNotNull, reason: 'rayon $rayon');
        final retour =
            rayonDepuisLaVue(cadre!.northWest, cadre.southEast, plafondKm: 200);
        expect(retour, isNotNull);
        expect(retour!, closeTo(rayon, rayon * 0.02),
            reason: 'rayon $rayon → cadre → $retour');
      }
    });

    test('sans rayon, aucun cadre — et surtout pas un cadre inventé', () {
      // Un client d'avant cette version n'a rien cadré. Lui fabriquer un
      // rectangle lui imposerait un zoom qu'il n'a pas choisi (règle 29).
      expect(cadreDepuisLeRayon(const LatLng(34.67, 3.26), null), isNull);
      expect(cadreDepuisLeRayon(const LatLng(34.67, 3.26), 0), isNull);
      expect(cadreDepuisLeRayon(const LatLng(34.67, 3.26), -3), isNull);
    });

    test('un cadre proche du pôle reste fini', () {
      // Hors sujet en Algérie, mais un cosinus qui tend vers zéro donnerait un
      // écart infini — et un NaN dans un cadrage fige la carte sans erreur.
      final cadre = cadreDepuisLeRayon(const LatLng(89.99, 0), 10);
      expect(cadre, isNotNull);
      expect(cadre!.east.isFinite, isTrue);
      expect(cadre.west.isFinite, isTrue);
    });
  });

  group('cadreEstPerime', () {
    test('vue identique au cadre enregistré : rien à proposer', () {
      expect(cadreEstPerime(5.0, 5.0), isFalse);
      expect(cadreEstPerime(6.0, 5.0), isFalse);
    });

    test('on a zoomé : le cadre ne couvre plus ce qu\'on regarde', () {
      // Le cas d'Alger : la liste montre 5 km, l'écran montre 1 km.
      expect(cadreEstPerime(1.0, 5.0), isTrue);
    });

    test('on a dézoomé : le cadre est trop étroit pour ce qu\'on regarde', () {
      expect(cadreEstPerime(30.0, 5.0), isTrue);
    });

    test('aucun cadre posé : la pastille a toujours quelque chose à dire', () {
      expect(cadreEstPerime(5.0, null), isTrue);
    });

    test('rayon de la vue inconnu : on ne dérange pas', () {
      // ⚠️ Redéployer la pastille sur une absence de mesure la ferait
      // réapparaître sans raison, et c'est exactement l'encombrement qu'on
      // venait de retirer.
      expect(cadreEstPerime(null, 5.0), isFalse);
      expect(cadreEstPerime(null, null), isFalse);
    });
  });
}
