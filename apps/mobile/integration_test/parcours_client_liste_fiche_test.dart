/// **Parcours client — la liste, puis la fiche** (étape 3 de
/// `docs/METHODE_TEST.md`).
///
/// ── Pourquoi celui-ci ────────────────────────────────────────────────────
///
/// C'est **ce que voient 95 % des utilisateurs**, et ça n'avait aucune
/// assertion. Les cinq parcours précédents éprouvent des écrans que quelques
/// dizaines de personnes ouvriront ; celui-ci éprouve l'écran d'accueil du
/// produit.
///
/// ── L'assertion, et sa contre-mesure ─────────────────────────────────────
///
/// À l'écran : une promo **précise**, fabriquée par le script juste avant, est
/// retrouvée par la recherche, puis ouverte, et sa fiche porte bien sa
/// description.
///
/// Côté serveur : le **compteur de vues de cette promo passe de `v` à `v+1`**.
/// C'est ce qui distingue « la fiche s'est affichée » de « la fiche a
/// réellement demandé la promo au serveur ». Un écran qui rendrait la fiche à
/// partir de la carte déjà chargée en liste — sans appeler `GET /promo/:id` —
/// afficherait exactement la même chose, et le commerçant ne verrait jamais
/// ses vues monter.
///
/// Le compteur est par **appareil unique** : le décor est effacé avant le
/// parcours (`reinitialiserAppareil`), donc l'app repart avec un identifiant
/// d'appareil neuf et compte pour une vue de plus à chaque passage. Les
/// lectures que le script fait pour mesurer viennent, elles, d'un autre
/// identifiant, et ne se comptent qu'une fois.
///
/// ── Pourquoi la recherche, et pas « la première carte » ──────────────────
///
/// Taper sur la première carte de l'accueil rendrait le parcours dépendant de
/// l'ordre du tri, donc de l'heure de publication de tout le décor. La
/// recherche par description désigne **une** promo, celle du script — et
/// éprouve au passage un chemin de plus.
///
/// ⚠️ La description est une **donnée**, pas un libellé traduit : la chercher
/// ne lie pas ce parcours à la langue de l'appareil (voir l'en-tête du
/// harnais).
///
/// ── Ce qu'il ne couvre PAS ───────────────────────────────────────────────
///
/// Les favoris, le partage, le signalement et la carte — trois gestes et un
/// écran qui méritent chacun leur parcours. Le signalement en particulier
/// écrirait dans la file de modération, sous les pieds du parcours admin.
library;

import 'package:echango_promo/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('la promo se retrouve dans la liste et s’ouvre en fiche',
      (tester) async {
    exigerIdentifiants({
      'TEST_PROMO_DESC': promoDescription,
      'TEST_COMMUNE_ID': communeCible,
    });

    await reinitialiserAppareil();
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('onboarding_completed', true);
    // ⚠️ **Sans commune sélectionnée, l'accueil n'affiche AUCUNE promo** — il
    // montre « Choisissez vos communes ». `reinitialiserAppareil` efface les
    // préférences, donc l'état de départ est justement celui-là. Le premier
    // passage de ce parcours l'a découvert en cherchant une carte qui ne
    // pouvait pas exister.
    //
    // La commune est posée dans le magasin, comme l'onboarding : le choix des
    // communes est un parcours à lui seul (écran dédié, plafond de 4,
    // cascade wilaya → commune), et le mêler à celui-ci ferait échouer l'un
    // pour des raisons appartenant à l'autre.
    // Le décor pose le POINT de recherche, plus une sélection de communes
    // (bascule 2026-08-12). Sans lui, l'accueil cadrerait sur le défaut
    // servi par le serveur, qui n'est pas forcément celui du décor.
    prefs.setDouble('client_position_lat', decorLatitude);
    prefs.setDouble('client_position_lng', decorLongitude);
    prefs.setString('client_position_consent_version', 'geo-2026-08-12');
    // Les promos du décor portent une photo absente de MinIO.
    ignorerErreursDeChargementDImage();

    app.main();
    await tester.pump(const Duration(seconds: 2));

    // ── 1. L'accueil ─────────────────────────────────────────────────────
    //
    // Reconnu à sa barre de recherche — le seul `TextField` de l'écran.
    await pomperJusqua(
      tester,
      find.byType(TextField),
      raison: 'l’accueil client ne s’est pas affiché',
    );

    // ── 2. Chercher LA promo ─────────────────────────────────────────────
    await tester.enterText(find.byType(TextField).first, promoDescription);
    await tester.pump(const Duration(milliseconds: 400));

    // ⚠️ **`find.text` ne convient PAS ici** : il matche aussi les
    // `EditableText`, donc le champ de recherche dans lequel on vient de taper
    // la description. Le premier passage a « trouvé » la promo alors qu'aucune
    // carte n'était affichée — l'assertion se vérifiait elle-même. On ne
    // regarde donc que les `Text`, ceux des cartes.
    int cartes() => find
        .byWidgetPredicate((w) => w is Text && w.data == promoDescription)
        .evaluate()
        .length;

    // Une seule carte doit rester. Exactement une, et non « au moins une » :
    // si la recherche ne filtrait pas, la promo serait quand même à l'écran et
    // le parcours passerait sans avoir rien éprouvé.
    await pomperJusquaVrai(
      tester,
      () => cartes() == 1,
      raison: 'la recherche n’a pas ramené « $promoDescription » '
          '(exactement une carte attendue)',
      limite: const Duration(seconds: 40),
    );

    // ── 3. Ouvrir la fiche ───────────────────────────────────────────────
    await taper(
      tester,
      find.byWidgetPredicate((w) => w is Text && w.data == promoDescription),
    );

    // La fiche est reconnue à son bouton de partage, absent de la liste : sans
    // ça, on confondrait « la fiche est ouverte » avec « la carte est encore
    // affichée derrière ».
    await pomperJusqua(
      tester,
      find.byIcon(Icons.share_outlined),
      raison: 'la fiche promo ne s’est pas ouverte',
    );
    expect(
      find.byWidgetPredicate((w) => w is Text && w.data == promoDescription),
      findsWidgets,
      reason: 'la fiche ouverte ne porte pas la description de la promo '
          'demandée — ce n’est pas la bonne promo',
    );
  });
}
