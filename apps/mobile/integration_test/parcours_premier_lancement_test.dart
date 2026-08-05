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
///      l'utilisateur atterrit sur un accueil sans commune ni rôle.
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
/// **Le bouton « Activer » de la localisation** — celui des deux écrans. Il
/// ouvre la boîte de dialogue **du système**, qu'`integration_test` ne peut pas
/// toucher. Le parcours emprunte donc le chemin du refus (« Plus tard » puis
/// « Continuer sans »), qui est aussi celui qui compte le plus : c'est lui qui
/// doit laisser l'app utilisable. La permission accordée relève d'un test
/// manuel, pas de celui-ci.
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

    // ── 2. Client → l'écran de localisation ──────────────────────────────
    await taper(tester, find.byIcon(Icons.person_outline));
    await pomperJusqua(
      tester,
      find.byIcon(Icons.location_on_outlined),
      raison: 'l’écran de localisation ne suit pas le choix « client »',
    );

    // ── 3. Refuser prend DEUX écrans, pas un ─────────────────────────────
    //
    // « Plus tard » ne termine pas l'onboarding : il mène à un écran de
    // seconde chance. C'est délibéré (`onboarding_navigation.dart`) — un
    // refus sur NOS écrans ne consomme pas la permission système, alors qu'un
    // refus sur la boîte native est définitif (`deniedForever`). D'où une
    // seconde demande, qui n'aurait aucun sens après un refus système.
    //
    // ⚠️ **Ce parcours a été écrit avec un écran de trop en moins**, et c'est
    // lui qui l'a dit : il attendait l'accueil, a trouvé « Activer la
    // localisation / Continuer sans » et l'a écrit dans son message d'échec.
    // Une relecture du code de navigation aurait pu le montrer ; elle ne
    // l'avait pas fait.
    //
    // Chaque bouton est désigné par son TYPE, jamais par son libellé :
    // « Activer » est un `FilledButton` sur les deux écrans, « Plus tard » un
    // `TextButton`, « Continuer sans » un `OutlinedButton`. Les trois types
    // suffisent à les séparer, dans n'importe quelle langue.
    await taper(tester, find.byType(TextButton));

    await pomperJusqua(
      tester,
      find.byType(OutlinedButton),
      raison: 'l’écran de seconde chance ne suit pas « Plus tard »',
    );
    await taper(tester, find.byType(OutlinedButton));

    // L'accueil est reconnu à sa barre d'onglets — la même icône que la carte
    // « commerçant » de l'étape 1, mais les deux écrans de localisation l'ont
    // fait disparaître entre les deux, donc aucune confusion possible.
    await pomperJusqua(
      tester,
      find.byIcon(Icons.storefront_outlined),
      raison: 'l’accueil client n’a pas suivi « Continuer sans »',
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
