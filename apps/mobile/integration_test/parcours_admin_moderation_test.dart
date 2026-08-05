/// **Parcours de modération admin** — masquer une promo signalée, depuis
/// l'écran (étape 3 de `docs/METHODE_TEST.md`).
///
/// ── Pourquoi celui-ci ────────────────────────────────────────────────────
///
/// C'est **le seul geste d'écran qui change ce que tous les clients voient**.
/// Un commerçant qui se trompe abîme sa propre vitrine ; un admin qui masque
/// retire une promo de l'accueil de tout le monde. C'était aussi le plus gros
/// écart du dépôt entre le pouvoir d'un écran et ce qu'on en savait : treize
/// écrans admin, un seul atteint par un parcours jusqu'ici.
///
/// ── L'assertion, en deux temps ───────────────────────────────────────────
///
/// À l'écran : la file passe de `n` à `n-1` tuiles. Côté serveur, la
/// contre-mesure du script vérifie que **la file du serveur a bougé elle
/// aussi**, et que c'est bien la promo visée qui en est sortie. Les deux
/// ensemble distinguent trois situations qu'un seul témoin confond :
///
///   · la tuile disparaît et le serveur ne bouge pas → l'écran ment ;
///   · le serveur bouge et la file reste à `n`       → l'écran ne se rafraîchit
///     pas, exactement le défaut trouvé le 2026-08-05 sur le compteur ;
///   · les deux bougent                              → le geste a porté.
///
/// ⚠️ **La contre-mesure a d'abord regardé au mauvais endroit.** Elle exigeait
/// que le nombre de promos servies au public baisse de un — et rendait ❌ sur
/// un produit parfaitement correct. `VISIBLE_MODERATION_STATUSES` ne contient
/// que `NORMALE` et `VERIFIEE_OK` : une promo **signalée est déjà retirée du
/// public** au moment du signalement. L'admin qui masque rend ce retrait
/// définitif, il ne retire pas quelque chose de visible. Le total public ne
/// pouvait donc pas bouger. *Une contre-mesure fondée sur une prémisse fausse
/// accuse le produit ; c'est le pire des faux négatifs, parce qu'il est
/// crédible.*
///
/// ── Comment les éléments sont désignés ───────────────────────────────────
///
/// L'action « masquer » est choisie **par la valeur** de son
/// `PopupMenuItem<String>` (`'masquer'`), jamais par son libellé traduit. La
/// file est comptée en `PromoModerationTile`, pas en lignes de texte : une
/// promo dont la description ressemble à une autre ne fausse rien.
///
/// ── Ce qu'il ne couvre PAS ───────────────────────────────────────────────
///
/// « Vérifier OK » et « Avertir », les deux autres branches du même menu, et
/// l'écran de détail. Ils ont leurs contrôles dans `test-admin-moderation.sh`.
/// Ce parcours répond à une seule question, celle qu'aucun banc ne peut poser :
/// **le geste fait depuis l'écran produit-il l'effet annoncé, pour le
/// public ?**
///
/// ⚠️ **Ce parcours MODIFIE le décor** — il masque une promo pour de bon. Il
/// passe donc en dernier dans `test-parcours-ecran.sh`, après les parcours qui
/// comparent des compteurs : masquer d'abord ferait échouer ceux-là sur un
/// chiffre périmé, et l'échec accuserait l'écran.
library;

import 'package:echango_promo/features/admin/widgets/promo_moderation_tile.dart';
import 'package:echango_promo/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('masquer une promo depuis la file la retire de la file',
      (tester) async {
    exigerIdentifiants({
      'TEST_PRO_EMAIL': proEmail,
      'TEST_PRO_PASSWORD': proPassword,
      'TEST_QUEUE': queueAttendue,
    });

    final avant = int.parse(queueAttendue);
    // ⚠️ Une file vide ne prouve rien : le parcours passerait sans avoir rien
    // masqué. On le dit ici plutôt que d'échouer plus loin sur un menu absent.
    expect(
      avant,
      greaterThan(0),
      reason:
          'la file de modération est vide — ce parcours n’a rien à masquer. '
          'Le décor doit poser au moins un signalement.',
    );

    await reinitialiserAppareil();
    (await SharedPreferences.getInstance())
        .setBool('onboarding_completed', true);
    // Les promos de la file portent la photo du décor, absente de MinIO.
    ignorerErreursDeChargementDImage();

    app.main();
    await tester.pump(const Duration(seconds: 2));

    // ── 1. Entrer en admin par SA porte ──────────────────────────────────
    //
    // L'espace commerçant, dont l'écran de connexion bascule en mode admin
    // dès qu'on saisit un e-mail. Pas de lien profond : ce serait éprouver un
    // chemin que personne n'emprunte.
    await pomperJusqua(
      tester,
      find.byIcon(Icons.storefront_outlined),
      raison: 'la barre d’onglets client n’est pas apparue',
    );
    await taper(tester, find.byIcon(Icons.storefront_outlined));

    await pomperJusqua(
      tester,
      find.byType(TextFormField),
      raison: 'l’écran de connexion ne s’est pas ouvert',
    );
    await saisir(tester, 0, proEmail);
    await saisir(tester, 1, proPassword);
    await taper(tester, find.byType(FilledButton));

    // ── 2. Le tableau de bord, puis la file ──────────────────────────────
    //
    // La tuile « signalements en attente » mène à la file : on l'ouvre par où
    // l'admin l'ouvre, et non par sa route.
    await pomperJusqua(
      tester,
      find.byIcon(Icons.flag_outlined),
      raison: 'le tableau de bord admin ne s’est pas affiché',
    );
    await taper(tester, find.byIcon(Icons.flag_outlined));

    int tuiles() => find.byType(PromoModerationTile).evaluate().length;

    await pomperJusquaVrai(
      tester,
      () => tuiles() == avant,
      raison: 'la file de modération n’affiche pas les $avant élément(s) '
          'servis par GET /admin/moderation/queue',
      limite: const Duration(seconds: 40),
    );

    // ── 3. Masquer la première promo ─────────────────────────────────────
    await taper(tester, find.byType(PopupMenuButton<String>).first);

    final masquer = find.byWidgetPredicate(
      (widget) => widget is PopupMenuItem<String> && widget.value == 'masquer',
    );
    await pomperJusqua(
      tester,
      masquer,
      raison: 'le menu d’action de la tuile ne s’est pas déployé',
    );
    await taper(tester, masquer);

    // ── 4. La file a-t-elle appris ? ─────────────────────────────────────
    //
    // C'est la moitié « écran » de l'assertion. L'autre moitié — la promo
    // n'est plus servie au public — est vérifiée par le script, avec le
    // serveur. Ni l'une ni l'autre ne suffit seule.
    await pomperJusquaVrai(
      tester,
      () => tuiles() == avant - 1,
      raison: 'après « masquer », la file affiche toujours $avant '
          'élément(s) — la promo est peut-être masquée sans que l’écran '
          'l’ait appris',
      limite: const Duration(seconds: 40),
    );
  });
}
