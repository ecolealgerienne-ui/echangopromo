/// Outillage commun aux parcours joués sur l'appareil — squelette (étage 4).
///
/// ── Pourquoi rien n'est cherché par son libellé (mode M6) ────────────────
///
/// Les widgets sont désignés par leur **icône**, leur **type**, leur **rang
/// dans une barre d'onglets**, ou une **donnée que le décor a posée** — jamais
/// par un texte traduit. Une recherche par libellé lierait le test à la langue
/// de l'appareil : il passerait au vert ici et échouerait sur un téléphone en
/// arabe, pour une raison sans rapport avec le défaut.
///
/// ── À placer dans ────────────────────────────────────────────────────────
///
///   apps/mobile/integration_test/harness.dart
///
/// avec, à côté, `apps/mobile/test_driver/integration_test.dart` :
///
///   import 'package:integration_test/integration_test_driver.dart';
///   Future<void> main() => integrationDriver();
///
/// ⚠️ Ce lanceur ne contient aucune logique et n'en contiendra jamais : il
/// tourne sur la machine de développement, pas sur l'appareil. Les deux moitiés
/// ne partagent pas de mémoire — y écrire une assertion la rendrait aveugle à
/// ce qui se passe à l'écran.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Identifiants — posés par scripts/provision-decor.sh
// ─────────────────────────────────────────────────────────────────────────────
//
// ⚠️ **Aucune valeur par défaut sur les identifiants, et c'est délibéré**
// (mode M3). Un test qui se rabattrait sur un compte imaginaire échouerait à la
// connexion en accusant l'écran de connexion. Absents, on le dit tout de suite
// et on nomme le script qui les pose.

const String merchantEmail = String.fromEnvironment('TEST_MERCHANT_EMAIL');
const String password =
    String.fromEnvironment('TEST_PASSWORD', defaultValue: 'motdepasse123');

/// La **valeur distinctive** qui identifie la ressource du décor.
///
/// ⚠️ Choisir une valeur réellement AFFICHÉE sur la carte de liste. Une
/// ressource s'identifie souvent par son prix et non par son nom, parce que
/// certains champs sont masqués tant qu'elle n'est pas prise (projection
/// expurgée).
const String prixDistinctif =
    String.fromEnvironment('TEST_PRIX_DISTINCTIF', defaultValue: '777');

/// Vérifie que le décor a fourni ses identifiants, et nomme le script sinon.
void requireCredentials(Map<String, String> attendus) {
  final manquants =
      attendus.entries.where((e) => e.value.isEmpty).map((e) => e.key).toList();
  if (manquants.isNotEmpty) {
    fail('--dart-define manquant(s) : ${manquants.join(", ")}\n'
        'Lancer scripts/provision-decor.sh et copier la commande qu\'il imprime.');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Isolation entre parcours
// ─────────────────────────────────────────────────────────────────────────────

/// Remet l'appareil dans un état neuf avant chaque parcours.
///
/// ⚠️ Sans ça, un parcours hérite de la session du précédent : il démarre
/// connecté, saute l'écran de connexion, et échoue plus loin sur un écran
/// qu'il n'attendait pas — en accusant cet écran-là (mode M8).
Future<void> resetDevice() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  // À ADAPTER : vider aussi le stockage sécurisé si la session y vit
  // (flutter_secure_storage : await const FlutterSecureStorage().deleteAll()).
}

// ─────────────────────────────────────────────────────────────────────────────
// Attente
// ─────────────────────────────────────────────────────────────────────────────

/// Attend qu'un `Finder` trouve quelque chose, ou échoue en DISANT quoi.
///
/// ⚠️ **`pumpAndSettle` ne convient pas ici.** Il attend l'absence
/// d'animation ; une liste chargée par le réseau n'anime rien pendant qu'elle
/// attend, et une animation continue (indicateur de chargement) ne se calme
/// jamais. On pompe donc à intervalle fixe jusqu'à la condition.
///
/// ⚠️ Le message [onTimeout] doit dire **ce qu'il y avait à l'écran** et **quoi
/// faire**. « Timeout » seul envoie chercher au mauvais endroit.
Future<void> pumpUntil(
  WidgetTester tester,
  Finder cible, {
  required String reason,
  String? onTimeout,
  Duration limite = const Duration(seconds: 30),
}) async {
  await pumpUntilTrue(
    tester,
    () => cible.evaluate().isNotEmpty,
    reason: reason,
    onTimeout: onTimeout,
    limite: limite,
  );
}

/// Attend la DISPARITION d'un `Finder`.
///
/// Utile comme preuve d'un effet : un bouton qui disparaît une fois l'action
/// faite prouve que le serveur a répondu et que l'état a été relu.
Future<void> pumpUntilGone(
  WidgetTester tester,
  Finder cible, {
  required String reason,
  String? onTimeout,
  Duration limite = const Duration(seconds: 30),
}) async {
  await pumpUntilTrue(
    tester,
    () => cible.evaluate().isEmpty,
    reason: reason,
    onTimeout: onTimeout,
    limite: limite,
  );
}

Future<void> pumpUntilTrue(
  WidgetTester tester,
  bool Function() condition, {
  required String reason,
  String? onTimeout,
  Duration limite = const Duration(seconds: 30),
}) async {
  const pas = Duration(milliseconds: 250);
  var ecoule = Duration.zero;
  while (ecoule < limite) {
    await tester.pump(pas);
    ecoule += pas;
    if (condition()) return;
  }
  fail('$reason — non atteint en ${limite.inSeconds}s.\n'
      '${onTimeout ?? "à l'écran : ${visibleTexts()}"}');
}

// ─────────────────────────────────────────────────────────────────────────────
// Désignation et navigation
// ─────────────────────────────────────────────────────────────────────────────

/// La ligne d'une liste dont un texte contient [needle], casse ignorée.
///
/// ⚠️ Casse ignorée : beaucoup de back-ends normalisent les noms de lieux ou de
/// personnes en MAJUSCULES sans que l'app le sache.
Finder rowContaining(String needle) {
  final voulu = needle.toLowerCase();
  return find.ancestor(
    of: find.byWidgetPredicate(
      (w) => w is Text && (w.data?.toLowerCase().contains(voulu) ?? false),
      description: '« $needle » (casse ignorée)',
    ),
    matching: find.byType(ListTile),
  );
}

/// Fait défiler jusqu'à ce que [cible] EXISTE dans l'arbre.
///
/// ⚠️ **`ListView.builder` ne construit que ce qui est à l'écran** (mode M7).
/// Une ligne plus bas dans la liste n'existe pas dans l'arbre, donc elle est
/// invisible à `find` — et le test conclut que le décor ne l'a pas posée. Le
/// diagnostic part alors dans la mauvaise direction.
///
/// ⚠️ On tire depuis une **coordonnée d'écran**, pas depuis un `Scrollable`
/// désigné par son type : les onglets d'un `TabBarView` en exposent plusieurs et
/// rien ne distingue celui qui est visible de celui qui dort à côté.
Future<void> scrollUntilFound(
  WidgetTester tester,
  Finder cible, {
  int maxDrags = 25,
}) async {
  for (var i = 0; i < maxDrags; i++) {
    if (cible.evaluate().isNotEmpty) return;
    await tester.dragFrom(
        tester.getCenter(find.byType(Scaffold).first), const Offset(0, -320));
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// Tape un élément après s'être assuré qu'il est visible.
///
/// ⚠️ Taper l'icône ne suffit pas : un bandeau peut la recouvrir, ou l'écran
/// peut ne pas avoir fini de se reconstruire. Le tap part alors dans le vide, et
/// l'assertion suivante attend trente secondes avant de conclure que l'écran ne
/// montre rien — en accusant l'écran.
Future<void> tapVisible(WidgetTester tester, Finder cible) async {
  await tester.ensureVisible(cible.first);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(cible.first);
  await tester.pump(const Duration(milliseconds: 600));
}

/// Ouvre l'onglet de rang [index].
///
/// Par son RANG, jamais par son libellé (mode M6).
Future<void> openTab(WidgetTester tester, int index) async {
  final onglets = find.byType(Tab);
  await pumpUntil(tester, onglets, reason: 'la barre d\'onglets');
  await tapVisible(tester, onglets.at(index));
}

/// Revient à l'écran précédent.
///
/// ⚠️ **Pas `tester.pageBack()`** : il exige une icône Material exacte ou un
/// bouton Cupertino, et échoue sur « One back button expected » alors que la
/// flèche est bien à l'écran.
Future<void> goBack(WidgetTester tester) async {
  final fleche = find.byIcon(Icons.arrow_back);
  if (fleche.evaluate().isNotEmpty) {
    await tapVisible(tester, fleche);
  } else if (find.byType(BackButton).evaluate().isNotEmpty) {
    await tapVisible(tester, find.byType(BackButton));
  } else {
    fail('Aucun retour trouvé — à l\'écran : ${visibleTexts()}');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Diagnostic
// ─────────────────────────────────────────────────────────────────────────────

/// Les textes réellement présents dans l'arbre — pour les messages d'échec.
///
/// C'est ce qui transforme « timeout » en un message actionnable.
String visibleTexts([int max = 25]) {
  final textes = find
      .byType(Text)
      .evaluate()
      .map((e) => (e.widget as Text).data)
      .whereType<String>()
      .where((s) => s.trim().isNotEmpty)
      .take(max)
      .toList();
  return textes.isEmpty ? '(aucun texte à l\'écran)' : textes.join(' | ');
}

/// Vrai si [valeur] apparaît quelque part à l'écran.
///
/// Sert aux assertions de VALEUR — ce que seul l'étage 4 peut voir : le serveur
/// sert le bon montant, mais l'utilisateur le voit-il, et ne le confond-il pas
/// avec un autre ?
bool screenHas(String valeur) => find.textContaining(valeur).evaluate().isNotEmpty;

// ─────────────────────────────────────────────────────────────────────────────
// Connexion
// ─────────────────────────────────────────────────────────────────────────────

/// Connecte un persona et attend son écran d'accueil.
///
/// À ADAPTER : la désignation des champs dépend de l'écran de connexion. Les
/// désigner par leur **type restreint à l'écran visé**, jamais par un index
/// global — un sélecteur de langue ou un lien d'inscription peut être du même
/// type et venir avant.
Future<void> loginAs(
  WidgetTester tester, {
  required String email,
  required Finder accueil,
}) async {
  await pumpUntil(tester, find.byType(TextField),
      reason: 'l\'écran de connexion',
      onTimeout: 'écran : ${visibleTexts()} — l\'app a-t-elle démarré ?');

  final champs = find.byType(TextField);
  await tester.enterText(champs.at(0), email);
  await tester.enterText(champs.at(1), password);
  await tester.pump(const Duration(milliseconds: 200));

  await tapVisible(tester, find.byType(FilledButton));

  await pumpUntil(tester, accueil,
      reason: 'l\'accueil après connexion',
      onTimeout: 'écran : ${visibleTexts()} — le compte est-il activé ? '
          'relancer scripts/provision-decor.sh');
}
