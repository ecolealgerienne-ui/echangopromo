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
