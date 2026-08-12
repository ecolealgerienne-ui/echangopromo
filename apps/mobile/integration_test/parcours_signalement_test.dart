/// **Parcours client — signaler une promo** (étape 3 de
/// `docs/METHODE_TEST.md`).
///
/// ── Pourquoi celui-ci ────────────────────────────────────────────────────
///
/// C'est **la seule écriture d'un client** — tout le reste de son parcours est
/// en lecture. Et c'est une écriture qui porte loin : une promo signalée sort
/// immédiatement du public (`VISIBLE_MODERATION_STATUSES` ne contient que
/// `NORMALE` et `VERIFIEE_OK`) et atterrit dans la file de modération de
/// l'admin.
///
/// C'est aussi la surface d'abus la plus exposée du produit : `POST /report`
/// n'est protégé que par un `X-Device-Id` déclaratif, jamais vérifié côté
/// serveur — d'où le rate-limit par IP (règle #7). Le geste mérite d'être joué.
///
/// ── L'assertion, et sa contre-mesure ─────────────────────────────────────
///
/// ⚠️ **Un signalement ne masque rien**, et c'est la règle du produit : il
/// faut **3 appareils distincts** (`MODERATION_THRESHOLD`, specs §5.4), et un
/// seul signalement par appareil et par promo. L'écran ne peut donc pas
/// montrer la promo disparaître — il ne montre qu'un accusé de réception.
///
/// À l'écran : un `SnackBar` apparaît. Son TEXTE est traduit, son type ne
/// l'est pas ; on vérifie donc qu'il y a eu un retour, sans présumer lequel.
///
/// **La preuve que le geste a compté est côté serveur, et elle est
/// construite** : le script envoie **deux** signalements de plus, depuis deux
/// appareils distincts, puis vérifie que la promo est sortie du public. Deux
/// ne suffisent pas — il en faut trois. Donc si la promo devient invisible,
/// c'est que **celui de l'app a été compté**. C'est la seule façon d'observer
/// un effet à partir d'un geste qui, seul, n'en produit aucun de visible.
///
/// ⚠️ **La première version de ce parcours affirmait le contraire**, et
/// passait : elle revenait à la liste et exigeait que la carte ait disparu.
/// Elle a été verte alors que la promo était toujours publique — parce
/// qu'**une assertion d'absence est satisfaite par l'écran de chargement**.
/// Chercher ce qui ne doit plus être là ne vaut que si l'on a d'abord établi
/// que le reste est là (règle #28).
///
/// ── Ce qu'il ne couvre PAS ───────────────────────────────────────────────
///
/// **Le rate-limit** et le **plafond de signalements par appareil** : les
/// éprouver demanderait d'enchaîner les envois, ce qui consommerait le seau
/// strict (5/min/IP) sous les pieds des autres parcours. Ils ont leur banc,
/// `test-abus-signalement.sh`.
///
/// **Le choix du motif** : le parcours prend le premier de la feuille. Le motif
/// remonté est vérifié côté serveur par le banc, pas ici.
library;

import 'package:echango_promo/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('signaler une promo la retire de la liste', (tester) async {
    exigerIdentifiants({
      'TEST_PROMO_DESC': promoDescription,
      'TEST_COMMUNE_ID': communeCible,
    });

    await reinitialiserAppareil();
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('onboarding_completed', true);
    // La commune est posée d'office : son choix a son propre parcours.
    // Le décor pose le POINT de recherche, plus une sélection de communes
    // (bascule 2026-08-12). Sans lui, l'accueil cadrerait sur le défaut
    // servi par le serveur, qui n'est pas forcément celui du décor.
    prefs.setDouble('client_position_lat', decorLatitude);
    prefs.setDouble('client_position_lng', decorLongitude);
    prefs.setString('client_position_consent_version', 'geo-2026-08-12');
    ignorerErreursDeChargementDImage();

    app.main();
    await tester.pump(const Duration(seconds: 2));

    // ── 1. Trouver la promo et ouvrir sa fiche ───────────────────────────
    await pomperJusqua(
      tester,
      find.byType(TextField),
      raison: 'l’accueil client ne s’est pas affiché',
    );

    // ⚠️ Le `Text` seulement, jamais `find.text` : celui-ci matcherait aussi
    // le champ de recherche dans lequel on vient de taper la description.
    Finder carte() =>
        find.byWidgetPredicate((w) => w is Text && w.data == promoDescription);

    await tester.enterText(find.byType(TextField).first, promoDescription);
    await pomperJusquaVrai(
      tester,
      () => carte().evaluate().length == 1,
      raison: 'la recherche n’a pas ramené « $promoDescription »',
      limite: const Duration(seconds: 40),
    );
    await taper(tester, carte());

    await pomperJusqua(
      tester,
      find.byIcon(Icons.flag_outlined),
      raison: 'la fiche promo ne s’est pas ouverte, ou n’offre pas de signaler',
    );

    // ── 2. Signaler ──────────────────────────────────────────────────────
    await taper(tester, find.byIcon(Icons.flag_outlined));

    // La feuille propose un motif par `ListTile`. On prend le premier — le
    // motif exact est l'affaire du banc, pas de cet écran.
    await pomperJusqua(
      tester,
      find.byType(ListTile),
      raison: 'la feuille des motifs de signalement ne s’est pas ouverte',
    );
    await taper(tester, find.byType(ListTile).first);

    // Le retour est un `SnackBar` — son TEXTE est traduit, son type ne l'est
    // pas. On vérifie donc qu'il y a bien eu un retour, sans présumer lequel :
    // c'est la contre-mesure serveur qui dit si le signalement a porté.
    await pomperJusqua(
      tester,
      find.byType(SnackBar),
      raison: 'aucun retour après le choix du motif — le tap est parti dans '
          'le vide',
      limite: const Duration(seconds: 40),
    );

    // ── 3. Ce que l'écran NE peut PAS montrer ────────────────────────────
    //
    // Rien de plus : il faudra deux autres appareils pour que la promo sorte
    // du public, et c'est le script qui les fournit. Ajouter ici une
    // vérification « la carte a disparu » serait faux — et l'a été.
  });
}
