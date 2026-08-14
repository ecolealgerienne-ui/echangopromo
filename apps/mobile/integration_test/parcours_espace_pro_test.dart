/// **Parcours de l'espace pro** — admin et agent, sur l'appareil (étape 3 de
/// `docs/METHODE_TEST.md`).
///
/// ── Un seul fichier, joué DEUX fois ──────────────────────────────────────
///
/// Les deux rôles aboutissent sur le **même écran** (`AdminDashboardScreen`,
/// qui adapte son titre) et sur le **même endpoint** (`GET /admin/dashboard`,
/// ouvert aux rôles `admin` et `agent`). Écrire deux fichiers, c'est deux
/// copies qui divergeront le jour où l'écran bougera (règle #30). Le rôle
/// arrive donc en `--dart-define`, et le script joue le parcours deux fois.
///
/// ── L'assertion, et pourquoi c'est celle-là ──────────────────────────────
///
/// Le tableau de bord affiche cinq compteurs. Le script les mesure
/// **auprès du serveur, avec le jeton de CE rôle-là**, et le parcours exige
/// de les retrouver à l'écran.
///
/// ⚠️ **Ce parcours était un contrôle de PÉRIMÈTRE, et il ne l'est plus.**
/// L'agent ne voyait que ses communes, l'admin voyait tout ; un agent à qui
/// l'on aurait servi les compteurs globaux n'aurait rien vu d'anormal — les
/// chiffres seraient plausibles, simplement pas les siens. Comparer aux
/// chiffres du serveur *pour ce rôle* était la seule façon de les distinguer.
///
/// Depuis le 2026-08-13, agent et admin reçoivent **les mêmes compteurs**. Le
/// parcours garde toute sa capacité à échouer — il mesure toujours auprès du
/// serveur avec le jeton du rôle, et refuse un écran qui afficherait autre
/// chose —, mais il a perdu son **motif** : ce n'est plus le cloisonnement
/// qu'il éprouve, c'est la cohérence entre ce que le serveur compte et ce que
/// l'écran montre.
///
/// **Ce qui distingue encore les deux rôles est ailleurs** : l'agent n'a ni le
/// journal d'audit ni l'écran de gestion des agents. C'est là qu'un contrôle
/// discriminant devrait porter désormais.
///
/// ── Une seule porte pour les deux rôles ──────────────────────────────────
///
/// Barre d'onglets → écran de connexion commerçant → **saisir un e-mail** au
/// lieu d'un numéro fait basculer ce même écran en mode pro (mot de passe au
/// lieu du PIN). Entrée volontairement discrète plutôt qu'une entrée de menu.
///
/// ⚠️ **Cette porte n'a servi que l'admin jusqu'au 2026-08-05** : la bascule
/// n'essayait que `POST /admin/login`, dont le service ne lit que la table
/// `admins`, et un agent y recevait « Identifiants invalides ». Le parcours
/// agent entrait alors par un lien profond, faute de mieux. La bascule tente
/// désormais l'agent quand l'admin refuse pour identifiants invalides, et **les
/// deux rôles empruntent ici le même chemin que l'utilisateur** — ce qui est
/// tout l'intérêt de les jouer.
///
/// ── Ce qu'il ne couvre PAS ───────────────────────────────────────────────
///
/// **Les actions**, délibérément : modérer, créer un agent, composer le
/// bandeau. Elles ont leurs bancs HTTP (`test-admin-moderation`,
/// `test-admin-agents`, `test-admin-highlight`) et les jouer ici modifierait
/// le décor sous les pieds des autres parcours. Ce parcours-ci répond à une
/// seule question, celle qu'aucun banc ne peut poser : **l'écran montre-t-il
/// ce que le serveur lui a servi ?**
library;

import 'package:echango_promo/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('l’espace pro affiche les compteurs DU SERVEUR, pour CE rôle',
      (tester) async {
    exigerIdentifiants({
      'TEST_PRO_ROLE': proRole,
      'TEST_PRO_EMAIL': proEmail,
      'TEST_PRO_PASSWORD': proPassword,
      'TEST_PRO_STATS': proStatsAttendues,
    });
    if (proRole != 'admin' && proRole != 'agent') {
      fail('TEST_PRO_ROLE vaut « $proRole » — attendu « admin » ou « agent ».');
    }

    final attendus = proStatsAttendues.split(',').map((s) => s.trim()).toList();
    // ⚠️ Cinq compteurs, pas « au moins un » : si le serveur en sert quatre,
    // c'est le contrat qui a changé et le parcours doit s'arrêter là plutôt
    // que de comparer ce qu'il a sous la main.
    expect(attendus, hasLength(5),
        reason: 'TEST_PRO_STATS doit porter les 5 compteurs de '
            'GET /admin/dashboard, séparés par des virgules — reçu : '
            '« $proStatsAttendues »');

    await reinitialiserAppareil();
    (await SharedPreferences.getInstance())
        .setBool('onboarding_completed', true);
    // Le décor pose des promos dont la photo n'existe pas dans MinIO ; leur
    // 404 ferait échouer ce parcours en accusant l'écran (voir le harnais).
    ignorerErreursDeChargementDImage();

    app.main();
    await tester.pump(const Duration(seconds: 2));

    // ── 1. Entrer par la porte, la même pour les deux rôles ──────────────
    await pomperJusqua(
      tester,
      find.byIcon(Icons.storefront_outlined),
      raison: 'la barre d’onglets client n’est pas apparue',
    );
    await taper(tester, find.byIcon(Icons.storefront_outlined));

    await pomperJusqua(
      tester,
      find.byType(TextFormField),
      raison: 'l’écran de connexion $proRole ne s’est pas ouvert',
    );

    // Par RANG : e-mail puis mot de passe. Les deux écrans partagent cette
    // structure — et côté commerçant, c'est la saisie de l'e-mail dans le
    // premier champ qui déclenche la bascule (`onChanged`, `contains('@')`).
    await saisir(tester, 0, proEmail);
    await saisir(tester, 1, proPassword);
    await taper(tester, find.byType(FilledButton));

    // ── 2. Les cinq compteurs du serveur, à l'écran ──────────────────────
    //
    // On attend que les CINQ soient présents ensemble. Un par un, on
    // conclurait sur un écran à moitié chargé.
    //
    // La comparaison se fait en sous-multi-ensemble : chaque valeur servie
    // doit être présente autant de fois qu'elle l'est côté serveur. Deux
    // compteurs à « 0 » exigent donc bien deux « 0 » à l'écran — sans ça, un
    // écran affichant un seul zéro passerait.
    bool tousPresents() {
      final restants = textesRendus().map(normaliserCompteur).toList();
      for (final attendu in attendus) {
        if (!restants.remove(attendu)) return false;
      }
      return true;
    }

    await pomperJusquaVrai(
      tester,
      tousPresents,
      raison: 'le tableau de bord $proRole n’affiche pas les compteurs servis '
          'par GET /admin/dashboard pour ce rôle '
          '(attendus : ${attendus.join(", ")})',
      limite: const Duration(seconds: 40),
    );
  });
}
