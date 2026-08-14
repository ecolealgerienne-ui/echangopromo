/// **Parcours client — la carte** (étape 3 de `docs/METHODE_TEST.md`).
///
/// ── Pourquoi celui-ci ────────────────────────────────────────────────────
///
/// C'est le dernier grand écran que **personne n'avait jamais ouvert**.
///
/// ⚠️ *En le préparant, j'ai d'abord conclu que la carte était vide : une
/// requête avec `minLat/maxLat` — les paramètres s'appellent
/// `north/south/east/west` — rendait « 0 commerce ». Elle en porte huit,
/// géolocalisés par `seed-demo.sh`. Une requête fausse ne prouve rien, elle en
/// a juste l'air (règle #38).*
///
/// ── L'assertion ──────────────────────────────────────────────────────────
///
/// Le marqueur d'un commerce isolé affiche **sa meilleure remise**. Ce chiffre
/// est calculé **par l'app** (`MapShop.bestDiscountPercent`) à partir des
/// promos que le serveur envoie — le script le recalcule donc de son côté,
/// depuis les prix servis. C'est le rôle d'un oracle de test, et la seule
/// façon de vérifier un affichage dérivé : le jour où la formule change d'un
/// seul côté, ce parcours le dit.
///
/// ⚠️ Le commerce choisi est celui dont la remise est **unique dans la zone** :
/// le marqueur n'affiche que « −XX% », donc deux commerces à la même remise
/// rendraient la désignation ambiguë et le parcours taperait sur l'un ou
/// l'autre en silence. Si aucune remise n'est unique, le script **refuse** au
/// lieu de choisir au hasard.
///
/// ── Ce qu'il ne couvre PAS ───────────────────────────────────────────────
///
/// **Les fonds de carte** : ils viennent d'un serveur de tuiles externe. Leur
/// échec est une erreur de chargement d'image, ignorée par le harnais — ce
/// parcours éprouve les marqueurs, pas OpenStreetMap.
///
/// **Le regroupement** (plusieurs commerces en un marqueur) et la
/// **troncature** à 300 commerces : les deux demandent un décor volumineux, et
/// la troncature est déjà éprouvée côté serveur par `test-client-carte.sh`.
library;

import 'package:echango_promo/features/client/widgets/map_shop_sheet.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:echango_promo/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('la carte montre le commerce et sa meilleure remise',
      (tester) async {
    exigerIdentifiants({
      'TEST_REMISE': remiseAttendue,
      'TEST_COMMERCE_NOM': commerceNom,
    });

    await reinitialiserAppareil();
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('onboarding_completed', true);
    // Le décor pose le POINT de recherche — plus aucune sélection de communes
    // (bascule géographique du 2026-08-12). Sans lui, l'accueil cadrerait
    // sur le défaut servi par le serveur, qui n'est pas celui du décor.
    prefs.setDouble('client_position_lat', decorLatitude);
    prefs.setDouble('client_position_lng', decorLongitude);
    prefs.setString('client_position_consent_version', 'geo-2026-08-12');
    // Les fonds de carte viennent d'un serveur de tuiles externe : leurs
    // échecs sont des erreurs d'image, sans rapport avec ce qu'on éprouve.
    ignorerErreursDeChargementDImage();

    app.main();
    await tester.pump(const Duration(seconds: 2));

    // ── 1. Ouvrir la carte par son onglet ────────────────────────────────
    await pomperJusqua(
      tester,
      find.byIcon(Icons.map_outlined),
      raison: 'la barre d’onglets client n’est pas apparue',
    );
    await taper(tester, find.byIcon(Icons.map_outlined));

    // ── 2. Le marqueur, et la remise DU SERVEUR ──────────────────────────
    //
    // La carte charge ses commerces d'après la zone visible, qui n'est connue
    // qu'une fois la carte posée : la fenêtre est donc large.
    final marqueur =
        find.byWidgetPredicate((w) => w is Text && w.data == remiseAttendue);

    // ⚠️ **Le marqueur individuel n'apparaît QUE si rien ne le regroupe.**
    // La carte agrège les commerces trop proches en grappes qui se scindent au
    // zoom : attendre le marqueur sans jamais zoomer suppose une densité
    // faible que rien ne garantit — et qui sera fausse en production bien
    // avant de l'être ici. Ce parcours a d'ailleurs échoué le 2026-08-12 sur
    // un décor à 13 commerces, en affichant « 11 » et « 2 » : le produit
    // fonctionnait, c'est le parcours qui supposait.
    //
    // On fait donc ce que fait un utilisateur : taper une grappe, qui zoome
    // dessus, jusqu'à ce que le marqueur se détache. Borné, parce qu'un
    // « jusqu'à ce que ça marche » sans borne est une boucle infinie déguisée.
    final grappe = find.byWidgetPredicate(
        (w) => w is Text && int.tryParse(w.data ?? '') != null);
    // Étiquettes des grappes au tour précédent — voir la sortie « inséparable »
    // plus bas.
    String? grappesPrecedentes;
    for (var essai = 0; essai < 8 && marqueur.evaluate().isEmpty; essai++) {
      await pomperJusquaVrai(
        tester,
        () => marqueur.evaluate().isNotEmpty || grappe.evaluate().isNotEmpty,
        raison: 'ni marqueur ni grappe sur la carte — elle n’a rien chargé',
        limite: const Duration(seconds: 30),
      );
      if (marqueur.evaluate().isNotEmpty) break;

      // ⚠️ **`grappe.first` sur un finder qui peut s'être vidé entre-temps
      // lève `Bad state: No element`**, et c'est exactement ce qui est arrivé
      // le 2026-08-13 : la carte se re-regroupe pendant l'animation de zoom,
      // donc l'élément vu par `pomperJusquaVrai` n'existe plus au moment du
      // tap. L'échec ne disait rien de la carte — juste que le parcours avait
      // supposé la stabilité entre deux instructions.
      final grappes = grappe.evaluate().toList();
      if (grappes.isEmpty) continue;

      // ⚠️ **La grappe LA PLUS PROCHE DU CENTRE, jamais `grappe.first`.**
      // Taper une grappe y zoome : en prendre une au hasard fait voyager la
      // caméra, et six taps plus tard on est à fond de zoom sur une pile
      // étrangère — la cible n'est plus à l'écran, et le parcours conclut
      // « le commerce n'est pas affiché » alors qu'il l'était au départ.
      // Mesuré le 2026-08-13 : l'écran final ne portait plus **ni marqueur ni
      // grappe**, juste l'attribution OpenStreetMap et les filtres.
      //
      // La carte s'ouvre centrée sur le point de recherche, et le décor pose
      // son commerce à côté : la grappe qui le contient est donc celle du
      // milieu. C'est aussi ce que ferait un humain — on zoome là où on
      // cherche, pas sur le premier amas venu.
      final centreEcran = tester.getCenter(find.byType(FlutterMap).first);
      Element plusProche = grappes.first;
      var meilleureDistance = double.infinity;
      for (final e in grappes) {
        final d = (tester.getCenter(find.byElementPredicate((x) => x == e)) -
                centreEcran)
            .distance;
        if (d < meilleureDistance) {
          meilleureDistance = d;
          plusProche = e;
        }
      }
      final cible = find.byElementPredicate((x) => x == plusProche);

      // ⚠️ **Une grappe de points CONFONDUS ne se scinde à aucun zoom.** Taper
      // six fois n'y change rien : les commerces ont les mêmes coordonnées.
      // Sans cette sortie, le parcours tournait jusqu'à la borne puis mourait
      // sur la course ci-dessus — un symptôme qui n'a aucun rapport avec la
      // cause. Le décor pose désormais chaque commerçant à SON point
      // (`provision-decor.sh`) et le script refuse une cible empilée, mais ce
      // banc doit savoir le DIRE plutôt que de tourner dans le vide.
      final etiquettes = grappes.map((e) => (e.widget as Text).data).join(',');
      if (etiquettes == grappesPrecedentes) {
        fail('la grappe « $etiquettes » ne se scinde pas après un zoom : les '
            'commerces qu’elle contient ont des coordonnées identiques, et '
            'aucun zoom ne les séparera. Le marqueur « $remiseAttendue » ne '
            'peut donc pas exister — c’est le décor qu’il faut regarder, pas '
            'la carte.');
      }
      grappesPrecedentes = etiquettes;

      await taper(tester, cible);
      await tester.pump(const Duration(seconds: 2));
    }

    await pomperJusquaVrai(
      tester,
      () => marqueur.evaluate().isNotEmpty,
      raison: 'aucun marqueur « $remiseAttendue » sur la carte après avoir '
          'ouvert les grappes — le commerce n’est pas affiché, ou pas à cet '
          'endroit',
      limite: const Duration(seconds: 60),
    );

    // ── 3. Taper le marqueur ouvre la fiche du commerce ──────────────────
    await taper(tester, marqueur);
    await pomperJusqua(
      tester,
      find.byType(MapShopSheet),
      raison: 'taper le marqueur n’ouvre pas la fiche du commerce',
    );
    expect(
      find.byWidgetPredicate((w) => w is Text && w.data == commerceNom),
      findsWidgets,
      reason: 'la fiche ouverte ne porte pas « $commerceNom » — ce n’est pas '
          'le bon commerce',
    );
  });
}
