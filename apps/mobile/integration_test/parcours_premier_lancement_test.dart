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
/// **Le refus de la localisation.** L'écran n'a plus qu'un bouton depuis la
/// mise en conformité 5.1.1(iv) du 2026-08-08, et il mène TOUJOURS à la boîte
/// de dialogue **du système** — qu'`integration_test` ne peut pas toucher.
/// `scripts/test-parcours-ecran.sh` accorde donc la permission par `pm grant`
/// avant de jouer : aucune boîte ne s'ouvre, et la traversée se vérifie. Le
/// chemin « refusé » (qui doit mener à l'accueil, pas à la carte) relève d'un
/// essai manuel, comme la boîte elle-même.
///
/// ⚠️ **Ce parcours suppose donc la permission ACCORDÉE.** Lancé à la main sans
/// l'octroi, il se bloque sur la boîte système puis échoue — ce que son message
/// d'échec dit, plutôt que d'accuser l'écran (règle #38).
library;

import 'package:echango_promo/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('un appareil neuf voit l’onboarding, et le retient',
      (tester) async {
    await reinitialiserAppareil();
    // Le parcours finit désormais sur la CARTE, dont le fond vient d'un
    // serveur de tuiles externe : une tuile qui ne descend pas ferait échouer
    // un parcours qui n'affirme rien sur les images.
    ignorerErreursDeChargementDImage();

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

    // ── 3. L'écran de localisation n'offre qu'une issue ──────────────────
    //
    // ⚠️ **C'est l'assertion que le refus d'Apple a rendue nécessaire**, et
    // elle porte sur une ABSENCE — donc elle n'a de sens qu'accompagnée de la
    // présence qui la borne (règle #28) : un bouton, exactement, et aucun
    // second bouton pour fermer le message sans demander. Deux refus
    // successifs sont partis de là (5.1.1(iv), 2026-08-05 puis 2026-08-07) :
    // « Activer la localisation » encourageait, « Continuer » permettait de
    // remettre la demande à plus tard.
    //
    // Les boutons sont comptés par leur TYPE, jamais par leur libellé : le
    // parcours doit rester vrai sur un appareil en arabe.
    expect(
      find.byWidgetPredicate((w) => w is FilledButton),
      findsOneWidget,
      reason: 'l’écran de localisation doit porter UN bouton, celui qui mène '
          'à la demande système',
    );
    expect(
      find.byWidgetPredicate((w) => w is TextButton || w is OutlinedButton),
      findsNothing,
      reason: 'un second bouton rouvre la porte au refus 5.1.1(iv) : Apple '
          'exige que le message mène toujours à la demande système',
    );

    await taper(tester, find.byWidgetPredicate((w) => w is FilledButton));

    // ── 4. La permission accordée mène à la CARTE ────────────────────────
    //
    // Pas à l'accueil : `requestLocationAndFinish` route sur `/carte` quand la
    // position est disponible — la carte « autour de moi » n'ayant d'intérêt
    // qu'avec une position. C'est aussi ce qui prouve que la demande a bien eu
    // lieu et qu'elle a abouti : sans permission, on atterrirait sur `/`.
    await pomperJusqua(
      tester,
      find.byType(FlutterMap),
      raison: 'la carte n’a pas suivi le bouton de localisation — si l’écran '
          'de localisation est encore là, la boîte système attend une réponse '
          'que le test ne peut pas donner : pré-accorder la permission '
          '(scripts/test-parcours-ecran.sh le fait)',
    );

    // ── 5. Ce qui a été retenu, dans le VRAI magasin ─────────────────────
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
