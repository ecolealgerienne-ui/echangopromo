/// Outillage commun aux parcours joués sur l'appareil (étape 3 de
/// `docs/METHODE_TEST.md`).
///
/// ── Pourquoi rien n'est cherché par son libellé ──────────────────────────
///
/// Les widgets sont désignés par leur **icône**, leur **type**, leur **rang
/// dans une barre d'onglets**, ou une **donnée que le décor a posée** — jamais
/// par un texte traduit. Une recherche par libellé lierait le test à la langue
/// de l'appareil : il passerait au vert ici et échouerait sur un téléphone en
/// arabe, pour une raison sans rapport avec le défaut.
///
/// L'app bascule fr/en/ar depuis juillet 2026 : ce n'est pas une précaution
/// théorique.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Identifiants — posés par scripts/provision-decor.sh
// ─────────────────────────────────────────────────────────────────────────────
//
// ⚠️ **Aucune valeur par défaut sur les identifiants, et c'est délibéré.** Un
// test qui se rabattrait sur un compte imaginaire échouerait à la connexion en
// accusant l'écran de connexion. Absents, on le dit tout de suite et on nomme
// le script qui les pose.

const String commercantTel = String.fromEnvironment('TEST_COMMERCANT_TEL');
const String commercantPin = String.fromEnvironment('TEST_COMMERCANT_PIN');

/// Plafond de promos actives **tel que le serveur le sert**, pas tel que l'app
/// le croit.
///
/// ⚠️ C'est l'assertion centrale du premier parcours. Le chiffre a été écrit en
/// dur dans les trois fichiers `.arb` jusqu'au 2026-08-05 (« Plafond de 5
/// promos atteint ») : porter `PROMO_ACTIVE_CAP` à 8 autorisait 8 publications
/// tout en affichant « 7 / 5 ». Aucun test unitaire ne pouvait le voir — la
/// valeur était dans une traduction.
const String plafondAttendu = String.fromEnvironment('TEST_PLAFOND');

/// Nombre de promos réellement en ligne au moment du décor.
const String enLigneAttendu = String.fromEnvironment('TEST_EN_LIGNE');

/// Vérifie que le décor a fourni ses identifiants, et nomme le script sinon.
void exigerIdentifiants(Map<String, String> attendus) {
  final manquants =
      attendus.entries.where((e) => e.value.isEmpty).map((e) => e.key).toList();
  if (manquants.isNotEmpty) {
    fail('--dart-define manquant(s) : ${manquants.join(", ")}\n'
        'Lancer ./scripts/test-parcours-ecran.sh, qui pose le décor et '
        'construit la ligne de commande.');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Isolation entre parcours
// ─────────────────────────────────────────────────────────────────────────────

/// Remet l'appareil dans un état neuf avant chaque parcours.
///
/// ⚠️ Sans ça, un parcours hérite de la session du précédent : il démarre
/// connecté, saute l'écran de connexion, et échoue plus loin sur un écran
/// qu'il n'attendait pas — en accusant cet écran-là.
///
/// ⚠️ `SharedPreferences.setMockInitialValues` **ne suffit pas sur l'appareil**
/// : il installe un faux magasin en mémoire, alors que l'app réelle lit le
/// magasin natif. On efface donc le vrai.
Future<void> reinitialiserAppareil() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
}

/// Laisse passer les échecs de **chargement d'image**, et rien d'autre.
///
/// ── Pourquoi c'est nécessaire ────────────────────────────────────────────
///
/// `flutter_test` fait échouer un test dès qu'une exception est signalée,
/// **même asynchrone et sans rapport avec ce qu'il éprouve**. Or le décor pose
/// des promos dont la `photoKey` désigne un objet qui n'existe pas dans MinIO
/// (`promo-photos/demo/photo.jpg`) : le tableau de bord tente de l'afficher,
/// reçoit un 404, et le parcours du compteur échoue en accusant le compteur.
///
/// ⚠️ **Et ça ne se voyait pas**, parce que l'image était en cache sur
/// l'émulateur depuis un passage précédent : l'app n'allait jamais la
/// chercher. Découvert le 2026-08-05 en repartant d'un appareil vierge — le
/// parcours passait pour une raison qui n'avait rien à voir avec lui.
///
/// ── Ce que ça ne fait PAS ────────────────────────────────────────────────
///
/// Ça n'avale pas « les erreurs » : **uniquement** celles émises par le
/// service de résolution d'images. Toute autre exception continue d'échouer le
/// parcours, par le gestionnaire précédent qu'on rappelle. Un `catch` large
/// ici transformerait le harnais en machine à rassurer (règle #28).
///
/// Le prix est assumé et il est nul aujourd'hui : aucun parcours n'affirme
/// quoi que ce soit sur les photos, et celui qui en publie une la vérifie par
/// la création côté serveur, pas par son affichage.
void ignorerErreursDeChargementDImage() {
  final precedent = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.library == 'image resource service') return;
    precedent?.call(details);
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Attente
// ─────────────────────────────────────────────────────────────────────────────

/// Attend qu'un `Finder` trouve quelque chose, ou échoue en DISANT quoi.
///
/// ⚠️ **`pumpAndSettle` ne convient pas ici.** Il attend l'absence
/// d'animation ; une liste chargée par le réseau n'anime rien pendant qu'elle
/// attend, et un indicateur de chargement ne se calme jamais. On pompe donc à
/// intervalle fixe jusqu'à la condition.
Future<void> pomperJusqua(
  WidgetTester tester,
  Finder cible, {
  required String raison,
  Duration limite = const Duration(seconds: 30),
}) async {
  await pomperJusquaVrai(
    tester,
    () => cible.evaluate().isNotEmpty,
    raison: raison,
    limite: limite,
  );
}

Future<void> pomperJusquaVrai(
  WidgetTester tester,
  bool Function() condition, {
  required String raison,
  Duration limite = const Duration(seconds: 30),
}) async {
  const pas = Duration(milliseconds: 250);
  var ecoule = Duration.zero;
  while (ecoule < limite) {
    await tester.pump(pas);
    ecoule += pas;
    if (condition()) return;
  }
  // ⚠️ Le message dit ce qu'il y avait à l'écran : « Timeout » seul envoie
  // chercher au mauvais endroit.
  fail('$raison — non atteint en ${limite.inSeconds}s.\n'
      'à l\'écran : ${textesRendus()}');
}

/// Tous les textes présents dans l'arbre, **spans compris**.
///
/// ⚠️ `Text.data` vaut `null` sur un `Text.rich`, et le compteur du tableau de
/// bord en est un (« 3 » en grand, « / 5 » en petit). S'en tenir à `.data`
/// rendait les parcours aveugles à la seule valeur qu'ils doivent surveiller.
///
/// ⚠️ **Ce qu'on a le droit d'en asserter.** Un CHIFFRE rendu, oui : il ne
/// dépend pas de la langue. Un LIBELLÉ, non : l'assertion passerait ici et
/// échouerait sur un appareil en arabe, pour une raison sans rapport avec le
/// défaut cherché. Pour désigner un widget, c'est l'icône ou le type — voir
/// l'en-tête de ce fichier.
///
/// Vivait dans `parcours_plafond_commercant_test.dart` jusqu'au 2026-08-05,
/// remontée ici quand un deuxième parcours en a eu besoin : le jour où un
/// compteur passe à `Text.rich`, un seul endroit doit s'en apercevoir.
List<String> textesRendus() {
  final rendus = <String>[];
  for (final element in find.byType(Text).evaluate()) {
    final widget = element.widget as Text;
    final texte = widget.data ?? widget.textSpan?.toPlainText();
    if (texte != null && texte.trim().isNotEmpty) rendus.add(texte.trim());
  }
  return rendus;
}

/// Ramène les espaces d'un compteur (« 3 / 5 ») à des espaces ordinaires.
///
/// ⚠️ Flutter rend l'espace fine insécable (U+202F) et l'insécable (U+00A0)
/// là où la typographie française les demande. Comparer à `'3 / 5'` écrit au
/// clavier échoue alors sur une différence **invisible dans le message
/// d'erreur** — on cherche le défaut pendant une heure avant de comprendre que
/// les deux chaînes se ressemblent sans être égales.
///
/// `\s` suffit, et c'est voulu : la classe est celle d'ECMAScript, qui inclut
/// déjà U+00A0 et U+202F. Recopier ces caractères en dur dans la source les
/// rendrait invisibles à la relecture et fragiles au copier-coller.
String normaliserCompteur(String texte) =>
    texte.replaceAll(RegExp(r'\s+'), ' ').trim();

// ─────────────────────────────────────────────────────────────────────────────
// Désignation
// ─────────────────────────────────────────────────────────────────────────────

/// Tape un élément après s'être assuré qu'il est visible.
///
/// ⚠️ Taper l'icône ne suffit pas : un bandeau peut la recouvrir, ou l'écran
/// peut ne pas avoir fini de se reconstruire. Le tap part alors dans le vide,
/// et l'assertion suivante attend trente secondes avant d'accuser l'écran.
Future<void> taper(WidgetTester tester, Finder cible) async {
  await tester.ensureVisible(cible.first);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(cible.first);
  await tester.pump(const Duration(milliseconds: 600));
}

/// Saisit du texte dans le n-ième champ de l'écran.
///
/// ⚠️ Par RANG, pas par libellé : les deux champs de connexion portent des
/// intitulés traduits. Le rang est stable tant que l'ordre du formulaire l'est
/// — et si l'ordre change, le parcours doit être relu de toute façon.
Future<void> saisir(WidgetTester tester, int rang, String valeur) async {
  final champs = find.byType(TextFormField);
  expect(champs.evaluate().length, greaterThan(rang),
      reason: 'Champ de rang $rang absent — à l\'écran : ${textesRendus()}');
  await tester.enterText(champs.at(rang), valeur);
  await tester.pump(const Duration(milliseconds: 200));
}
