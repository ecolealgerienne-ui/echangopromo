/// **Parcours client — la ville par défaut, et le geste qui la fixe.**
///
/// ── Les deux scénarios que ce fichier éprouve ───────────────────────────────
///
/// Ils viennent du client, formulés le 2026-08-13 :
///
///   1. un nouveau client a Djelfa par défaut, avec ses promos ; on lui propose
///      d'enregistrer une position, et **aux connexions suivantes il est envoyé
///      directement sur cette ville** ;
///   2. il explore la carte, choisit une autre ville, et on lui propose de la
///      prendre comme ville par défaut.
///
/// C'est le geste central du produit depuis la suppression du découpage
/// administratif : le point du client est devenu son **seul** repère, et rien
/// ne l'éprouvait.
///
/// ── ⚠️ Ce qui n'est PAS éprouvable sur cette machine, et pourquoi ───────────
///
/// La branche « il active le GPS, on le positionne sur sa ville » du scénario 1.
/// Le GPS de cet émulateur est figé sur `37.421998, -122.084` (Mountain View) et
/// `adb emu geo fix` **ne le met pas à jour** : `dumpsys location` montrait un
/// relevé vieux de trois jours et demi malgré des commandes qui rendent `OK`.
/// C'est un défaut de la machine, du même ordre que l'antivirus qui casse
/// Gradle — pas du produit.
///
/// Ces parcours tournent donc **sans GPS** (`SANS_GPS=oui`), ce qui est de
/// toute façon la seule façon d'éprouver un point ENREGISTRÉ : un capteur actif
/// recentrerait la carte ailleurs à chaque relevé, et on mesurerait le capteur.
///
/// ── Ce qui remplace le « prochain lancement » ───────────────────────────────
///
/// Un `flutter drive` ne lance l'app qu'une fois. Le second test simule donc le
/// lancement suivant à l'endroit exact où il se joue : les préférences sont
/// **posées avant** `app.main()`, comme les aurait laissées la session
/// précédente, et on vérifie que l'app s'ouvre bien sur cette ville. C'est
/// précisément ce que promet le scénario 1.
library;

import 'package:echango_promo/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

/// Nom d'un commerce de la ville pré-enregistrée — il doit apparaître dans la
/// liste. Fourni par le script, qui le tient du **serveur** : recopier un nom
/// ici ferait échouer le parcours le jour où le décor change de libellé.
const String villeCommerce = String.fromEnvironment('TEST_VILLE_COMMERCE');

/// Nom d'un commerce d'une AUTRE ville, hors du rayon. Il ne doit PAS
/// apparaître — c'est ce qui distingue « la liste suit le point » de « la liste
/// sert tout ce qui existe ».
const String villeCommerceAilleurs =
    String.fromEnvironment('TEST_VILLE_COMMERCE_AILLEURS');

const String villeLat = String.fromEnvironment('TEST_VILLE_LAT');
const String villeLng = String.fromEnvironment('TEST_VILLE_LNG');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// ── Scénario 1, second temps : « aux connexions suivantes, cette ville » ──
  ///
  /// Le point est posé **avant** le démarrage, comme l'aurait laissé la session
  /// précédente. L'app doit s'ouvrir dessus — et le prouver par ce qu'elle
  /// SERT, pas par un centre de carte qu'on ne peut pas lire de l'extérieur.
  testWidgets('la ville enregistrée décide de ce que le client voit',
      (tester) async {
    exigerIdentifiants({
      'TEST_VILLE_COMMERCE': villeCommerce,
      'TEST_VILLE_COMMERCE_AILLEURS': villeCommerceAilleurs,
      'TEST_VILLE_LAT': villeLat,
      'TEST_VILLE_LNG': villeLng,
    });

    await reinitialiserAppareil();
    ignorerErreursDeChargementDImage();
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('onboarding_completed', true);
    prefs.setDouble('client_position_lat', double.parse(villeLat));
    prefs.setDouble('client_position_lng', double.parse(villeLng));
    prefs.setString('client_position_consent_version', 'geo-2026-08-12');

    app.main();
    await tester.pump(const Duration(seconds: 2));

    // ── La liste sert les promos de CETTE ville ─────────────────────────────
    //
    // ⚠️ Une présence, PUIS une absence — et jamais l'absence seule. « le
    // commerce d'ailleurs n'est pas là » est vrai pendant tout le chargement,
    // donc vrai avant même que la liste existe. On établit d'abord que la liste
    // est garnie de la bonne ville ; l'absence ne veut dire quelque chose
    // qu'après (règle 28).
    await pomperJusquaVrai(
      tester,
      () => textesRendus().any((t) => t.contains(villeCommerce)),
      raison:
          'la liste ne montre pas « $villeCommerce » : l’app n’a pas ouvert '
          'sur la ville enregistrée, ou elle ne sert pas ses promos',
      limite: const Duration(seconds: 45),
    );

    expect(
      textesRendus().any((t) => t.contains(villeCommerceAilleurs)),
      isFalse,
      reason: 'la liste montre « $villeCommerceAilleurs », qui est hors du '
          'rayon : elle ne suit pas le point enregistré mais sert tout ce qui '
          'existe',
    );
  });

  /// ── Scénario 1, premier temps : la proposition d'enregistrer ─────────────
  ///
  /// Aucun point enregistré : la carte s'ouvre sur le défaut du serveur, et le
  /// produit doit **proposer** de l'enregistrer. Avant le 2026-08-13, rien ne
  /// le proposait — il fallait remarquer un bouton flottant libellé « Chercher
  /// autour de ce point » pour comprendre qu'on pouvait fixer sa ville.
  testWidgets('sans ville enregistrée, l’app propose d’en fixer une',
      (tester) async {
    await reinitialiserAppareil();
    ignorerErreursDeChargementDImage();
    (await SharedPreferences.getInstance())
        .setBool('onboarding_completed', true);

    app.main();
    await tester.pump(const Duration(seconds: 2));

    await pomperJusqua(
      tester,
      find.byIcon(Icons.map_outlined),
      raison: 'la barre d’onglets client n’est pas apparue',
    );
    await taper(tester, find.byIcon(Icons.map_outlined));

    // ⚠️ On cherche le BOUTON de la proposition, pas son texte : le libellé
    // dépend de la langue de l'appareil, que ce parcours ne choisit pas.
    // `savePointProposeAccept` est rendu dans un `FilledButton` propre au
    // bandeau — l'écran n'en porte pas d'autre tant qu'aucune fiche n'est
    // ouverte.
    await pomperJusquaVrai(
      tester,
      () => find.byType(FilledButton).evaluate().isNotEmpty,
      raison: 'aucune proposition d’enregistrer une ville n’est apparue sur la '
          'carte — le client n’a aucun moyen de découvrir ce geste',
      limite: const Duration(seconds: 45),
    );

    // Le point n'est pas encore enregistré : la proposition ne doit rien avoir
    // écrit tant qu'on ne l'a pas acceptée.
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getDouble('client_position_lat'),
      isNull,
      reason: 'un point a été enregistré sans que personne n’accepte la '
          'proposition — le consentement n’en est plus un',
    );
  });
}
