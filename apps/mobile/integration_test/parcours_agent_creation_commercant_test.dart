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
/// Côté serveur, le script vérifie deux choses : **le compte se connecte** avec
/// le téléphone et le PIN saisis à l'écran — c'est ce qui distingue un compte
/// réellement créé d'une ligne affichée — et il est **dans la commune de
/// l'agent**. La seconde est la plus importante : elle éprouve la frontière de
/// zone, celle-là même dont l'absence a produit l'IDOR agent → promo (P5).
///
/// ── La commune n'est pas choisie au hasard ───────────────────────────────
///
/// Un agent ne peut créer que dans **ses** communes. Prendre la première de la
/// cascade ferait refuser la création par le serveur, et l'échec accuserait le
/// formulaire. Le script sert donc le nom de la wilaya et de la commune de
/// l'agent (`GET /agent/me`), et le parcours les choisit **par leur texte** —
/// des données de la base, pas des libellés traduits.
///
/// ── ⚠️ L'entrée reste un lien, faute de porte ────────────────────────────
///
/// Aucun écran de l'app ne mène à `/agent` : la bascule e-mail de la connexion
/// commerçant appelle `POST /admin/login`, qui ne connaît que les admins. C'est
/// un point produit ouvert, pas un choix de ce parcours — voir
/// `docs/status_v0.1.md`. Le jour où une porte existe, seule l'étape 1 change.
///
/// ── Ce qu'il ne couvre PAS ───────────────────────────────────────────────
///
/// **La première promo** proposée par la boîte de dialogue juste après la
/// création : le parcours répond « plus tard ». C'est un autre écran
/// (`/agent/promo/new/:id`) et un autre geste, couvert côté serveur par
/// `test-agent-promo.sh`.
///
/// **La photo de la boutique** et **la position GPS**, facultatives toutes les
/// deux ; la seconde ouvre en plus une boîte de dialogue du système.
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

  testWidgets('un agent crée un commerçant dans SA commune', (tester) async {
    exigerIdentifiants({
      'TEST_PRO_EMAIL': proEmail,
      'TEST_PRO_PASSWORD': proPassword,
      'TEST_COMMERCANT_TEL': commercantTel,
      'TEST_COMMERCANT_PIN': commercantPin,
      'TEST_WILAYA_NOM': wilayaNom,
      'TEST_COMMUNE_NOM': communeNom,
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
    await ouvrirLien(tester, '/agent');
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

    // La cascade : wilaya puis commune, chacune choisie par son NOM.
    for (final attendu in [wilayaNom, communeNom]) {
      final liste = find.byType(DropdownButtonFormField<String>);
      await pomperJusqua(
        tester,
        liste,
        raison: 'la cascade wilaya → commune n’est pas apparue',
      );
      // La wilaya d'abord (rang 0), la commune ensuite (rang 1) — la seconde
      // ne se remplit qu'une fois la première choisie.
      await taper(tester, liste.at(attendu == wilayaNom ? 0 : 1));
      final option = find.byWidgetPredicate(
        (w) => w is Text && w.data == attendu,
      );
      await pomperJusqua(
        tester,
        option,
        raison: '« $attendu » n’est pas proposé dans la cascade',
      );
      await taper(tester, option.last);
    }

    // ── 4. Le PIN, sous la ligne de flottaison ───────────────────────────
    await defilerJusquaVrai(
      tester,
      () => find.byType(TextFormField).evaluate().length >= 2,
      raison: 'les champs PIN n’ont jamais été atteints',
    );
    final champs = find.byType(TextFormField).evaluate().length;
    await saisir(tester, champs - 2, commercantPin);
    await saisir(tester, champs - 1, commercantPin);

    await defilerJusquaVrai(
      tester,
      () => find.byType(FilledButton).evaluate().isNotEmpty,
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
          'probablement été refusée (commune hors zone ? téléphone déjà pris ?)',
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
