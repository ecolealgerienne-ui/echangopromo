/// **Décor — retoucher les prix des promos déjà en base, par l'écran.**
///
/// ── Pourquoi une passe séparée ──────────────────────────────────────────────
///
/// Les 40 promos du décor à trois villes ont été créées avec une échelle de
/// prix qui ne variait **que** selon le rang de la promo : 1000/700, 1100/650…
/// 1400/500. Les cinq remises allaient donc de 30 % à 64 % — les mêmes pour
/// tous les commerçants.
///
/// Conséquence visible sur la carte : les trois marqueurs d'une ville
/// affichaient tous « −64 % », puisque le marqueur porte la **meilleure**
/// remise du commerce et qu'elles étaient égales. Trois points indiscernables,
/// et tout tri par remise sans objet. Constaté à Hassi Bahbah le 2026-08-13.
///
/// ⚠️ **On ne peut pas simplement les recréer** : le plafond de 5 créations par
/// 24 h et par commerçant est atteint. L'édition, elle, n'est plafonnée par
/// rien — c'est la seule voie disponible aujourd'hui, et elle emprunte un écran
/// réel comme la création.
///
/// ── ⚠️ Ce que cette passe NE fait pas ───────────────────────────────────────
///
/// Elle ne touche ni la description, ni la catégorie, ni la photo : rouvrir le
/// formulaire suffirait à les réécrire, et une retouche qui change plus que ce
/// qu'elle annonce est indiscernable d'une régression. Seuls les deux champs de
/// prix sont saisis.
///
/// ── Un seul lancement, comme la série ───────────────────────────────────────
///
/// Même raison : `--dart-define` est résolu à la compilation, donc un
/// commerçant par lancement imposerait une compilation par commerçant. La liste
/// tient dans une valeur, la boucle est dans l'app.
library;

import 'package:echango_promo/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

/// `tel:pin` séparés par des virgules — l'ordre fixe le décalage de l'échelle
/// de prix, donc il doit être **le même** qu'à la création.
const String commercantsSerie = String.fromEnvironment('TEST_COMMERCANTS');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('retoucher les prix pour que chaque commerçant ait son échelle',
      (tester) async {
    exigerIdentifiants({'TEST_COMMERCANTS': commercantsSerie});

    final comptes = commercantsSerie
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map((e) => (e.split(':')[0], e.split(':')[1]))
        .toList();
    expect(comptes, isNotEmpty,
        reason: 'TEST_COMMERCANTS ne porte aucun couple « tel:pin »');

    await reinitialiserAppareil();
    ignorerErreursDeChargementDImage();
    (await SharedPreferences.getInstance())
        .setBool('onboarding_completed', true);

    app.main();
    await tester.pump(const Duration(seconds: 2));

    final retouchees = <String>[];

    for (var m = 0; m < comptes.length; m++) {
      final (tel, pin) = comptes[m];

      await pomperJusqua(
        tester,
        find.byIcon(Icons.storefront_outlined),
        raison: 'la barre d’onglets client n’est pas apparue (avant $tel)',
      );
      await taper(tester, find.byIcon(Icons.storefront_outlined));
      await pomperJusqua(
        tester,
        find.byType(TextFormField),
        raison: 'l’écran de connexion commerçant ne s’est pas ouvert ($tel)',
      );
      await saisir(tester, 0, tel);
      await saisir(tester, 1, pin);
      await taper(tester, find.byType(FilledButton));

      // ── « Mes promos » ────────────────────────────────────────────────────
      await pomperJusqua(
        tester,
        find.byIcon(Icons.add),
        raison: 'le tableau de bord ne s’est pas affiché ($tel)',
      );
      // ⚠️ L'entrée « mes promos » est un `TextButton`, pas une icône — et ce
      // tableau de bord en porte **six**. Prendre `.first` viserait donc au
      // hasard : j'avais écrit « c'est le seul », c'était faux, et un
      // commentaire faux vaut moins que pas de commentaire.
      //
      // On vise le bouton par son LIBELLÉ, en acceptant les deux langues que
      // l'émulateur peut servir. ⚠️ Un appareil en arabe ferait échouer cette
      // recherche — c'est une limite assumée d'un producteur de décor, et elle
      // est dite plutôt que découverte.
      await taper(
        tester,
        find.ancestor(
          of: find.byWidgetPredicate((w) =>
              w is Text && (w.data == 'Tout voir' || w.data == 'See all')),
          matching: find.byType(TextButton),
        ),
      );
      await pomperJusqua(
        tester,
        find.byType(PopupMenuButton<String>),
        raison: 'la liste « mes promos » ne s’est pas ouverte ($tel)',
      );

      // ⚠️ Le nombre de lignes se COMPTE à l'écran : il varie d'un commerçant à
      // l'autre, et le supposer ferait sortir de la liste au premier absent.
      final lignes = find.byType(PopupMenuButton<String>).evaluate().length;
      debugPrint('[RETOUCHE] $tel : $lignes promo(s) à l’écran');

      for (var i = 0; i < lignes; i++) {
        // ⚠️ La liste se reconstruit après chaque enregistrement — on relit
        // donc le finder à chaque tour plutôt que de garder des éléments d'un
        // tour précédent, qui seraient détachés de l'arbre.
        final menus = find.byType(PopupMenuButton<String>);
        if (menus.evaluate().length <= i) break;
        await taper(tester, menus.at(i));
        await pomperJusqua(
          tester,
          find.byType(PopupMenuItem<String>),
          raison: 'le menu de la promo ${i + 1} ne s’est pas déployé ($tel)',
        );
        // « Modifier » est la PREMIÈRE entrée ; la seconde est publier/arrêter.
        await taper(tester, find.byType(PopupMenuItem<String>).first);

        await pomperJusqua(
          tester,
          find.byIcon(Icons.add_a_photo_outlined),
          raison: 'le formulaire d’édition ne s’est pas ouvert '
              '($tel, promo ${i + 1})',
        );

        // Champs par RANG : 0 description, 1 prix avant, 2 prix après. On ne
        // touche QUE les deux prix — voir l'en-tête.
        final prixAvant = 1000 + i * 100;
        final prixApres = 700 - i * 50 - m * 30;
        await saisir(tester, 1, '$prixAvant');
        await saisir(tester, 2, '$prixApres');

        await taper(tester, find.byType(FilledButton));

        // Retour à la liste : c'est le signal que l'enregistrement est passé.
        await pomperJusquaVrai(
          tester,
          () => find.byType(PopupMenuButton<String>).evaluate().isNotEmpty,
          raison: 'après enregistrement de la promo ${i + 1} de $tel, la liste '
              'n’est pas revenue — la sauvegarde a peut-être échoué',
          limite: const Duration(seconds: 60),
        );
        retouchees.add('$tel#${i + 1}');
      }

      // ── Retour au tableau de bord, puis déconnexion ──────────────────────
      await taper(tester, find.byType(BackButtonIcon));
      await pomperJusqua(
        tester,
        find.byIcon(Icons.account_circle_outlined),
        raison: 'le tableau de bord n’est pas revenu ($tel)',
      );
      await taper(tester, find.byIcon(Icons.account_circle_outlined));
      await pomperJusqua(
        tester,
        find.byType(PopupMenuItem<String>),
        raison: 'le menu du compte ne s’est pas déployé ($tel)',
      );
      await taper(tester, find.byType(PopupMenuItem<String>).last);
      await tester.pump(const Duration(seconds: 2));
    }

    debugPrint('[RETOUCHE] ${retouchees.length} promo(s) retouchée(s)');
  });
}
