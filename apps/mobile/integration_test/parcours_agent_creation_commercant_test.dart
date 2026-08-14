/// **Parcours agent — créer un commerçant** (étape 3 de
/// `docs/METHODE_TEST.md`).
///
/// ── Pourquoi celui-ci ────────────────────────────────────────────────────
///
/// C'est **le geste métier de l'agent**, et sa raison d'exister : il se
/// déplace en boutique et inscrit le commerçant à sa place. Jusqu'ici, l'agent
/// n'avait qu'un tableau de bord éprouvé — un écran qui montre, pas un écran
/// qui fait.
///
/// ── L'assertion, et sa contre-mesure ─────────────────────────────────────
///
/// À l'écran : le commerce créé apparaît dans la liste de l'agent, sous le nom
/// que le parcours vient de saisir.
///
/// Côté serveur, le script vérifie que **le compte se connecte** avec le
/// téléphone et le PIN saisis à l'écran — c'est ce qui distingue un compte
/// réellement créé d'une ligne affichée.
///
/// ⚠️ **Il vérifiait aussi qu'il naissait dans la commune de l'agent**, et
/// c'était la contre-mesure la plus importante : elle éprouvait la frontière
/// dont l'absence avait produit l'IDOR agent → promo (P5). Le chantier « agent
/// global » du 2026-08-13 supprime cette frontière par décision produit — il
/// n'y a plus de commune à comparer, et plus de refus à attendre.
///
/// Ce que ce parcours éprouve encore, et qui n'est pas rien : la **position**
/// reste obligatoire sur cet écran, et c'est ce qui empêche une tournée de
/// fabriquer des fiches invisibles.
///
/// ── L'entrée : la même que l'admin ───────────────────────────────────────
///
/// Barre d'onglets → connexion commerçant → e-mail. Un agent, c'est un admin
/// avec deux fonctionnalités en moins, pas un autre produit. Cette porte ne
/// servait que l'admin jusqu'au 2026-08-05 — voir `docs/status_v0.1.md`.
///
/// ── Ce qu'il ne couvre PAS ───────────────────────────────────────────────
///
/// **La première promo** proposée par la boîte de dialogue juste après la
/// création : le parcours répond « plus tard ». C'est un autre écran
/// (`/agent/promo/new/:id`) et un autre geste, couvert côté serveur par
/// `test-agent-promo.sh`.
///
/// **La photo de la boutique**, facultative.
///
/// ⚠️ Ce paragraphe disait « **et la position GPS**, facultatives toutes les
/// deux » — faux depuis le 2026-08-12, et faux à deux titres : la position est
/// **obligatoire** sur cet écran, et le parcours la capture bel et bien
/// (étape 4 bis). Un « ce qu'il ne couvre pas » qui liste une chose couverte
/// fait chercher un trou qui n'existe pas.
library;

import 'package:echango_promo/domain/enums/categorie.dart';
import 'package:echango_promo/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('un agent crée un commerçant, positionné', (tester) async {
    exigerIdentifiants({
      'TEST_PRO_EMAIL': proEmail,
      'TEST_PRO_PASSWORD': proPassword,
      'TEST_COMMERCANT_TEL': commercantTel,
      'TEST_COMMERCANT_PIN': commercantPin,
    });

    // Le nom du commerce est dérivé du téléphone, unique par construction :
    // c'est lui qu'on cherchera dans la liste, et deux passages ne doivent pas
    // se confondre.
    final nomCommerce =
        'Commerce agent ${commercantTel.substring(commercantTel.length - 6)}';

    await reinitialiserAppareil();
    (await SharedPreferences.getInstance())
        .setBool('onboarding_completed', true);
    ignorerErreursDeChargementDImage();

    app.main();
    await tester.pump(const Duration(seconds: 2));

    // ── 1. Entrer, se connecter ──────────────────────────────────────────
    await pomperJusqua(
      tester,
      find.byIcon(Icons.storefront_outlined),
      raison: 'la barre d’onglets client n’est pas apparue',
    );
    await taper(tester, find.byIcon(Icons.storefront_outlined));
    await pomperJusqua(
      tester,
      find.byType(TextFormField),
      raison: 'l’écran de connexion agent ne s’est pas ouvert',
    );
    await saisir(tester, 0, proEmail);
    await saisir(tester, 1, proPassword);
    await taper(tester, find.byType(FilledButton));

    // ── 2. Tableau de bord → liste des commerces → nouveau ───────────────
    //
    // La tuile « commerces actifs » mène à la liste : on y va par où l'agent y
    // va, pas par la route.
    await pomperJusqua(
      tester,
      find.byIcon(Icons.storefront_outlined),
      raison: 'le tableau de bord agent ne s’est pas affiché',
    );
    await taper(tester, find.byIcon(Icons.storefront_outlined));

    await pomperJusqua(
      tester,
      find.byIcon(Icons.add_business_outlined),
      raison: 'la liste des commerces de l’agent n’offre pas la création '
          '(le bouton n’apparaît que pour un agent, pas pour un admin)',
    );
    await taper(tester, find.byIcon(Icons.add_business_outlined));

    // ── 3. Le formulaire ─────────────────────────────────────────────────
    await pomperJusqua(
      tester,
      find.byType(DropdownButtonFormField<Categorie>),
      raison: 'le formulaire de création ne s’est pas ouvert',
    );
    await saisir(tester, 0, nomCommerce);
    await saisir(tester, 1, commercantTel);
    await saisir(tester, 2, 'Rue du parcours agent');

    await taper(tester, find.byType(DropdownButtonFormField<Categorie>));
    await pomperJusqua(
      tester,
      find.byType(DropdownMenuItem<Categorie>),
      raison: 'le menu des catégories ne s’est pas déployé',
    );
    await taper(tester, find.byType(DropdownMenuItem<Categorie>).last);

    // ⚠️ **La cascade wilaya → commune était ici**, et c'était le bloc
    // d'interaction le plus long du parcours : deux menus déroulants dont le
    // second ne se remplissait qu'une fois le premier choisi, chacun visé par
    // le NOM de la commune de l'agent — la première venue aurait fait refuser
    // la création par le serveur, et l'échec aurait accusé le formulaire.
    // Retirée le 2026-08-13 avec le découpage administratif.

    // ── 4. Le PIN, sous la ligne de flottaison ───────────────────────────
    await defilerJusquaVrai(
      tester,
      () => find.byType(TextFormField).evaluate().length >= 2,
      raison: 'les champs PIN n’ont jamais été atteints',
    );
    final champs = find.byType(TextFormField).evaluate().length;
    await saisir(tester, champs - 2, commercantPin);
    await saisir(tester, champs - 1, commercantPin);

    // ── 4 bis. La position, désormais OBLIGATOIRE ici ───────────────────
    //
    // ⚠️ **Nouveau depuis le 2026-08-12**, et c'est le geste qui manquait à ce
    // parcours : l'agent est physiquement dans le commerce, donc sa capture est
    // la seule juste par construction — la route serveur l'EXIGE
    // (`CreateCommercantByAgentDto`), et l'écran refuse avant même de partir.
    //
    // Sans ce bloc, le parcours restait bloqué sur le formulaire et accusait le
    // téléphone ou la zone : le message d'échec parlait de « téléphone déjà
    // pris ? », très loin de la vraie cause.
    await defilerJusquaVrai(
      tester,
      () => find.byIcon(Icons.my_location_outlined).evaluate().isNotEmpty,
      raison: 'le bouton de localisation n’a jamais été atteint',
    );
    // Désigné par son ICÔNE, jamais par son libellé : celui-ci est traduit, et
    // il change selon que la position est facultative ou requise.
    await taper(tester, find.byIcon(Icons.my_location_outlined));
    // La capture passe par le GPS de l'appareil : sur émulateur, c'est la
    // position simulée de l'AVD. On attend qu'elle soit affichée en clair —
    // le champ montre les coordonnées une fois captées, ce qui est le seul
    // signal fiable que le formulaire les a bien reçues.
    await pomperJusquaVrai(
      tester,
      () => find
          .byWidgetPredicate((w) =>
              w is Text &&
              RegExp(r'^-?\d+\.\d+, -?\d+\.\d+$').hasMatch(w.data ?? ''))
          .evaluate()
          .isNotEmpty,
      raison: 'la position n’a pas été captée — localisation activée sur '
          'l’émulateur ? une position simulée est-elle définie ?',
      limite: const Duration(seconds: 45),
    );

    await defilerJusqua(
      tester,
      find.byType(FilledButton),
      raison: 'le bouton de création n’a jamais été atteint',
    );
    await taper(tester, find.byType(FilledButton));

    // ── 5. « Ajouter une première promo ? » → plus tard ──────────────────
    //
    // La boîte de dialogue confirme la création. On répond par son
    // `TextButton` (« plus tard »), le `FilledButton` menant au formulaire de
    // promo — un autre geste, un autre parcours.
    await pomperJusqua(
      tester,
      find.byType(AlertDialog),
      raison: 'la confirmation de création n’est pas apparue — la création a '
          'probablement été refusée (téléphone déjà pris ? position non captée ?)',
      limite: const Duration(seconds: 60),
    );
    await taper(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextButton),
        ));

    // ── 6. Le commerce est dans la liste de l'agent ──────────────────────
    await pomperJusquaVrai(
      tester,
      () => find
          .byWidgetPredicate((w) => w is Text && w.data == nomCommerce)
          .evaluate()
          .isNotEmpty,
      raison: 'le commerce « $nomCommerce » n’apparaît pas dans la liste de '
          'l’agent après sa création',
      limite: const Duration(seconds: 40),
    );
  });
}
