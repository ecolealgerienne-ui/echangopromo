/// **Premier parcours joué sur l'appareil** — le compteur d'emplacements du
/// commerçant (étape 3 de `docs/METHODE_TEST.md`).
///
/// ── Pourquoi celui-ci d'abord ────────────────────────────────────────────
///
/// Le critère de la méthode est : *quelle valeur affichée tromperait le plus si
/// elle était fausse ?* Ici, c'est ce compteur. Il ne décore pas l'écran : il
/// dit au commerçant **s'il peut encore publier**. Faux, il l'envoie soit
/// buter sur un refus qu'il ne comprend pas, soit renoncer à publier alors
/// qu'il avait la place.
///
/// Et il n'a pas été choisi par intuition : **il a été faux deux fois le
/// 2026-08-05**, de deux façons qu'aucun test unitaire ne pouvait voir.
///
///   1. `my_promos_screen` affichait « 0 / 5 » et cinq barres vides tant que
///      `GET /promo/me/slots` n'avait pas répondu — c'est-à-dire *des
///      emplacements libres*, sans rien en savoir.
///   2. Le plafond était écrit **en toutes lettres dans les trois `.arb`**
///      (« Plafond de 5 promos atteint »). Porter `PROMO_ACTIVE_CAP` à 8
///      autorisait 8 publications tout en affichant « 7 / 5 ». La valeur
///      vivait dans une traduction : ni le compilateur, ni `flutter test`, ni
///      `check_server_rules.dart` ne pouvaient l'atteindre.
///
/// C'est exactement ce que ce parcours empêche de revenir : il compare le
/// chiffre **rendu à l'écran** à celui que le serveur a servi au décor.
///
/// ── Ce qu'il ne couvre PAS, volontairement ───────────────────────────────
///
/// L'onboarding est marqué comme fait avant le démarrage. Ce parcours éprouve
/// le compteur, pas le premier lancement — mélanger les deux ferait échouer
/// l'un pour des raisons appartenant à l'autre. L'onboarding mérite son propre
/// parcours ; son absence est déclarée ici plutôt que passée sous silence.
library;

import 'package:echango_promo/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('le compteur d’emplacements affiche le plafond DU SERVEUR',
      (tester) async {
    exigerIdentifiants({
      'TEST_COMMERCANT_TEL': commercantTel,
      'TEST_COMMERCANT_PIN': commercantPin,
      'TEST_PLAFOND': plafondAttendu,
      'TEST_EN_LIGNE': enLigneAttendu,
    });

    await reinitialiserAppareil();
    // L'onboarding est déclaré fait : voir l'en-tête de ce fichier.
    (await SharedPreferences.getInstance())
        .setBool('onboarding_completed', true);

    app.main();
    await tester.pump(const Duration(seconds: 2));

    // ── Aller à l'espace commerçant ────────────────────────────────────────
    // Désigné par son ICÔNE, jamais par « Espace commerçant » : ce libellé est
    // traduit, et le parcours doit passer sur un appareil en arabe.
    await pomperJusqua(
      tester,
      find.byIcon(Icons.storefront_outlined),
      raison: 'la barre d’onglets client n’est pas apparue',
    );
    await taper(tester, find.byIcon(Icons.storefront_outlined));

    // ── Connexion ──────────────────────────────────────────────────────────
    await pomperJusqua(
      tester,
      find.byType(TextFormField),
      raison: 'l’écran de connexion commerçant ne s’est pas ouvert',
    );
    await saisir(tester, 0, commercantTel);
    await saisir(tester, 1, commercantPin);
    await taper(tester, find.byType(FilledButton));

    // ── Le tableau de bord, et son compteur ────────────────────────────────
    //
    // ⚠️ On attend la VALEUR, pas l'écran. Attendre « le tableau de bord est
    // affiché » laisserait passer le défaut n°1 : l'écran était bien là, avec
    // un compteur de repli inventé. Ce qu'on veut savoir, c'est quand la
    // mesure du serveur est arrivée.
    final attendu = '$enLigneAttendu / $plafondAttendu';
    await pomperJusquaVrai(
      tester,
      () => textesRendus().any((t) => normaliserCompteur(t) == attendu),
      raison: 'le compteur d’emplacements n’a jamais affiché « $attendu » '
          '(mesure servie par GET /promo/me/slots)',
      limite: const Duration(seconds: 40),
    );

    // ⚠️ Et le plafond ne doit apparaître NULLE PART sous une autre valeur.
    // C'est ce qui attrape la traduction figée : si un `.arb` réintroduit un
    // « / 5 » en dur alors que le serveur en sert 3, les deux coexistent à
    // l'écran et le parcours doit le refuser — pas se contenter d'avoir trouvé
    // le bon quelque part.
    final concurrents = textesRendus()
        .map(normaliserCompteur)
        .where((t) => RegExp(r'^\d+ / \d+$').hasMatch(t))
        .where((t) => t != attendu)
        .toList();
    expect(
      concurrents,
      isEmpty,
      reason: 'un second compteur affiche autre chose que « $attendu » : '
          '$concurrents — une valeur figée quelque part ?',
    );
  });
}
