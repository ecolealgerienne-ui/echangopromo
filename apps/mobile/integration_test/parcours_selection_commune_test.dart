/// **Parcours client — choisir ses communes** (étape 3 de
/// `docs/METHODE_TEST.md`).
///
/// ── Pourquoi celui-ci ────────────────────────────────────────────────────
///
/// C'est **l'écran vers lequel l'accueil pousse tout nouvel utilisateur** :
/// sans commune sélectionnée, la liste n'affiche aucune promo et propose
/// « choisir mes communes ». Le parcours client précédent l'a contourné en
/// posant la commune dans le magasin local — en déclarant qu'il faudrait le
/// couvrir. C'est fait ici.
///
/// Il éprouve la chaîne complète de la sélection : l'état vide → l'écran de
/// choix → la cascade wilaya → la case cochée → la confirmation → **et le
/// retour, où les promos apparaissent enfin**.
///
/// ── L'assertion, et pourquoi elle porte sur une promo ────────────────────
///
/// On n'attend pas « des promos » : on attend **une promo précise**, servie
/// par le serveur pour cette commune-là (`GET /promo?communeIds=…`). C'est ce
/// qui distingue « la liste s'est remplie » de « la liste s'est remplie avec
/// ce que ce filtre-là doit rendre ». Une sélection qui n'enverrait pas la
/// commune au serveur afficherait, elle aussi, des promos.
///
/// Et le magasin natif est relu en fin de parcours : la sélection doit
/// **survivre**, sinon l'utilisateur la refait à chaque lancement.
///
/// ── Ce qu'il ne couvre PAS ───────────────────────────────────────────────
///
/// Le **plafond de 4 communes** (`kMaxSelectedCommunes`), qui désactive les
/// cases une fois atteint : il demande un décor à cinq communes peuplées, et
/// il est déjà tenu côté serveur par le DTO. Et la **modification** d'une
/// sélection existante — ce parcours part d'un appareil neuf, c'est-à-dire du
/// cas que tout le monde traverse une fois.
library;

import 'package:echango_promo/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('choisir une commune fait apparaître SES promos', (tester) async {
    exigerIdentifiants({
      'TEST_WILAYA_NOM': wilayaNom,
      'TEST_COMMUNE_NOM': communeNom,
      'TEST_COMMUNE_ID': communeCible,
      'TEST_PROMO_DESC': promoDescription,
    });

    await reinitialiserAppareil();
    (await SharedPreferences.getInstance())
        .setBool('onboarding_completed', true);
    ignorerErreursDeChargementDImage();

    app.main();
    await tester.pump(const Duration(seconds: 2));

    // ── 1. L'état vide, et son invitation ────────────────────────────────
    //
    // ⚠️ On vérifie l'état de DÉPART : sans lui, un appareil qui aurait gardé
    // une sélection ferait passer le parcours sans qu'il ait rien choisi.
    // L'accueil est reconnu à sa barre de recherche : on attend qu'il soit
    // bâti avant de chercher quoi que ce soit dedans.
    await pomperJusqua(
      tester,
      find.byType(TextField),
      raison: 'l’accueil client ne s’est pas affiché',
    );

    // ⚠️ **`Icons.tune` existe DEUX fois sur cet écran** : les filtres dans la
    // barre du haut, puis l'invitation de l'état vide. `.first` tape sur les
    // filtres — c'est ce qu'a fait le premier passage, avant d'attendre un
    // écran de sélection qui ne venait pas.
    //
    // ⚠️ Ni `find.byType(FilledButton)` ni `w is FilledButton` ne retrouvent ce
    // bouton : `FilledButton.icon` construit une sous-classe privée, et les
    // deux tentatives ont échoué sur un bouton pourtant affiché. On désigne
    // donc par POSITION — mais on **vérifie la position** en exigeant
    // exactement deux icônes : si l'écran en gagne ou en perd une, le parcours
    // le dit au lieu de taper ailleurs en silence.
    await defilerJusquaVrai(
      tester,
      () => find.byIcon(Icons.tune).evaluate().length >= 2,
      raison: 'l’accueil ne propose pas de choisir ses communes — l’appareil '
          'n’est pas vierge, ou l’état vide a changé',
    );
    expect(
      find.byIcon(Icons.tune),
      findsNWidgets(2),
      reason: 'l’écran ne porte plus exactement deux boutons « tune » '
          '(filtres, puis invitation) — la désignation par position n’est '
          'plus fiable, relire cet écran',
    );
    final inviterChoixCommune = find.byIcon(Icons.tune).last;
    expect(
      find.byWidgetPredicate((w) => w is Text && w.data == promoDescription),
      findsNothing,
      reason: 'une promo est déjà affichée alors qu’aucune commune n’est '
          'choisie — le filtre ne filtre pas',
    );
    await taper(tester, inviterChoixCommune);

    // ── 2. La cascade : wilaya, puis la commune ──────────────────────────
    await pomperJusqua(
      tester,
      find.byType(DropdownButtonFormField<String>),
      raison: 'l’écran de sélection des communes ne s’est pas ouvert',
    );
    await taper(tester, find.byType(DropdownButtonFormField<String>));
    final optionWilaya =
        find.byWidgetPredicate((w) => w is Text && w.data == wilayaNom);
    await pomperJusqua(
      tester,
      optionWilaya,
      raison: 'la wilaya « $wilayaNom » n’est pas proposée',
    );
    await taper(tester, optionWilaya.last);

    // La commune est cochée par son NOM — une donnée de la base, pas un
    // libellé traduit. Sa case est un `CheckboxListTile` parmi d'autres.
    final caseCommune = find.ancestor(
      of: find.byWidgetPredicate((w) => w is Text && w.data == communeNom),
      matching: find.byType(CheckboxListTile),
    );
    await pomperJusqua(
      tester,
      caseCommune,
      raison: 'la commune « $communeNom » n’apparaît pas dans « $wilayaNom »',
    );
    await taper(tester, caseCommune);

    // ── 3. Confirmer ─────────────────────────────────────────────────────
    //
    // Le bouton est désactivé tant que rien n'est coché : s'il ne réagit pas,
    // c'est que la case n'a pas pris — et l'étape suivante le dira.
    await taper(tester, find.byType(FilledButton));

    // ── 4. Les promos DE CETTE COMMUNE apparaissent ──────────────────────
    await pomperJusquaVrai(
      tester,
      () => find
          .byWidgetPredicate((w) => w is Text && w.data == promoDescription)
          .evaluate()
          .isNotEmpty,
      raison: 'après le choix de « $communeNom », l’accueil n’affiche toujours '
          'pas « $promoDescription », que le serveur sert pour cette commune',
      limite: const Duration(seconds: 40),
    );

    // ── 5. La sélection survit-elle ? ────────────────────────────────────
    //
    // Dans le VRAI magasin, celui que l'app relira au prochain lancement à
    // froid. Sans ça, on n'aurait montré qu'un affichage d'un jour.
    final retenues = (await SharedPreferences.getInstance())
        .getStringList('selected_commune_ids');
    expect(
      retenues,
      contains(communeCible),
      reason: 'la commune choisie n’est pas retenue — l’utilisateur devra '
          'refaire ce choix à chaque lancement',
    );
  });
}
