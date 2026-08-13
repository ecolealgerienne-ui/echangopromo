/// **Parcours du premier lancement** — splash, choix du rôle, localisation
/// (étape 3 de `docs/METHODE_TEST.md`).
///
/// ── Pourquoi celui-ci ────────────────────────────────────────────────────
///
/// C'est le seul écran que **100 % des utilisateurs voient**, et le seul qui
/// ne doit se voir **qu'une fois**. Les deux défauts qu'il peut porter sont
/// tous les deux invisibles au développeur, dont l'appareil a déjà fait
/// l'onboarding :
///
///   1. l'onboarding revient à chaque lancement (`markCompleted()` qui
///      n'écrit pas, ou qui écrit là où la redirection ne lit pas) ;
///   2. l'onboarding ne s'affiche jamais (marqué fait trop tôt) — et
///      l'utilisateur atterrit sur un accueil sans rôle choisi.
///
/// Aucun test unitaire ne les attrape : les deux dépendent du magasin
/// `SharedPreferences` **natif**, et `setMockInitialValues` installe justement
/// un faux magasin en mémoire qui répondrait ce qu'on veut entendre.
///
/// ── Ce qu'il ne couvre PAS, et pourquoi c'est écrit ──────────────────────
///
/// **La branche « commerçant » du choix de rôle.** Elle mène directement à
/// `/commercant` sans passer par la localisation. Elle n'est pas couverte
/// ici, et ce n'est pas un oubli : `splashShownThisLaunch` est une variable
/// **de processus** (`lib/app/launch_state.dart`). Un second parcours dans le
/// même processus ne reverrait donc jamais le splash, la redirection
/// n'enverrait plus sur `/onboarding`, et le test partirait droit sur
/// l'accueil — au vert, sans avoir rien éprouvé. **Un parcours d'onboarding
/// par lancement d'app, pas deux.** La couvrir demande un second
/// `flutter drive` sur son propre fichier.
///
/// **Le bouton « Activer » de la localisation.** Il ouvre la boîte de dialogue
/// **du système**, qu'`integration_test` ne peut pas toucher. Le parcours
/// emprunte donc « Continuer », qui est aussi le chemin qui compte le plus :
/// c'est lui qui doit laisser l'app utilisable. La permission accordée relève
/// d'un test manuel, pas de celui-ci.
///
/// ⚠️ **L'invitation à activer la localisation n'est plus dans l'onboarding**
/// depuis le refus d'Apple du 2026-08-05 : elle vit sur la carte. Ce parcours
/// vérifie donc qu'après « Continuer », on arrive bien à l'accueil — et pas
/// sur une seconde demande.
library;

import 'package:echango_promo/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('un appareil neuf voit l’onboarding, et le retient',
      (tester) async {
    await reinitialiserAppareil();

    // ⚠️ On vérifie l'état de DÉPART, sinon un `clear()` sans effet rendrait
    // tout le parcours vide de sens : l'app afficherait l'accueil, on
    // conclurait « l'onboarding ne revient pas » sans l'avoir jamais vu.
    expect(
      (await SharedPreferences.getInstance()).getBool('onboarding_completed'),
      isNull,
      reason: 'l’appareil n’est pas neuf — le parcours n’éprouverait rien',
    );

    app.main();

    // ── 1. Le splash, puis le choix du rôle ──────────────────────────────
    //
    // Le splash dure ~1,6 s d'animation plus 500 ms de pause. On n'attend pas
    // « le splash », on attend l'écran d'APRÈS : c'est lui qui prouve que la
    // décision a été prise, et l'attendre couvre l'animation sans avoir à en
    // recopier la durée ici (elle vivrait alors à deux endroits).
    await pomperJusqua(
      tester,
      find.byIcon(Icons.person_outline),
      raison: 'le choix du rôle n’est pas apparu après le splash',
    );
    expect(
      find.byIcon(Icons.storefront_outlined),
      findsOneWidget,
      reason: 'la carte « commerçant » manque au choix du rôle',
    );

    // ── 2. Client → l'accueil, directement ───────────────────────────────
    //
    // ⚠️ **Il y avait ici un écran de localisation, supprimé le 2026-08-12.**
    // Le client n'a plus aucune permission à accorder pour voir des promos :
    // sans point enregistré, le serveur cadre sur son défaut. L'invitation à
    // activer la localisation reste contextuelle, sur la carte — c'est ce
    // placement qui a levé le refus App Store 5.1.1(iv) du 2026-08-05, et le
    // supprimer d'ici ne le remet pas en cause.
    //
    // ⚠️ Ce que ce parcours doit surtout attraper désormais : `markCompleted()`
    // n'était appelé QUE depuis l'écran supprimé. S'il manque au choix du rôle,
    // l'onboarding revient à chaque lancement — et rien d'autre ne le dirait
    // (voir l'assertion sur le magasin natif, plus bas).
    await taper(tester, find.byIcon(Icons.person_outline));
    await pomperJusqua(
      tester,
      find.byIcon(Icons.storefront_outlined),
      raison: 'l’accueil client n’a pas suivi le choix « client »',
    );

    // ── 4. Ce qui a été retenu, dans le VRAI magasin ─────────────────────
    //
    // C'est l'assertion qui compte : sans elle, on n'a montré que la
    // traversée d'un jour. `SharedPreferences.getInstance()` lit ici le
    // magasin natif de l'appareil, celui-là même que la redirection
    // consultera au prochain lancement à froid.
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool('onboarding_completed'),
      isTrue,
      reason: 'l’onboarding n’est pas marqué fait — il reviendra à chaque '
          'lancement',
    );
    expect(
      prefs.getString('onboarding_role'),
      'client',
      reason: 'le rôle choisi n’a pas été retenu',
    );
  });
}
