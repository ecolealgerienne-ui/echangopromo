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
///
/// ── ⚠️ `find.byType` compare le type EXACT ───────────────────────────────
///
/// Il ne matche pas les sous-classes. Les constructeurs `.icon` de Material
/// (`FilledButton.icon`, `ElevatedButton.icon`…) rendent une sous-classe
/// **privée** : `find.byType(FilledButton)` ne les voit pas. *Trouvé le
/// 2026-08-05 sur l'invitation « choisir mes communes », bien affichée et
/// pourtant introuvable.* Pour ces cas, `find.byWidgetPredicate((w) => w is
/// FilledButton)`, qui accepte l'héritage.
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

// ── Espace pro (admin et agent) ──────────────────────────────────────────────
//
// Le MÊME parcours est joué deux fois, une fois par rôle : les deux
// aboutissent sur `AdminDashboardScreen`, qui adapte son titre et **le
// périmètre de ses chiffres**. C'est justement ce qu'on veut éprouver — un
// agent qui verrait les compteurs globaux serait une fuite de périmètre, pas
// un défaut d'affichage.

/// `admin` ou `agent` — décide de la route d'entrée et de rien d'autre.
const String proRole = String.fromEnvironment('TEST_PRO_ROLE');
const String proEmail = String.fromEnvironment('TEST_PRO_EMAIL');
const String proPassword = String.fromEnvironment('TEST_PRO_PASSWORD');

/// Nombre d'éléments dans la file de modération, **servi par le serveur**
/// (`GET /admin/moderation/queue`, champ `total`).
const String queueAttendue = String.fromEnvironment('TEST_QUEUE');

/// Description **unique** de la promo que le parcours client doit retrouver.
///
/// ⚠️ Fabriquée par le script pour ce passage-là (horodatée). Chercher « Promo
/// du décor » ramènerait autant de résultats qu'il y a eu de décors, et
/// l'assertion « une seule carte » deviendrait fausse pour une raison qui n'a
/// rien à voir avec l'écran.
const String promoDescription = String.fromEnvironment('TEST_PROMO_DESC');

/// Commune à poser dans le magasin local avant le parcours client.
///
/// ⚠️ **Elle ne cadre plus l'accueil depuis le 2026-08-12** : le client cherche
/// autour d'un point, plus dans des communes. Elle reste utile aux parcours
/// **agent**, dont le périmètre d'autorisation est toujours la commune.
const String communeCible = String.fromEnvironment('TEST_COMMUNE_ID');

/// Point du décor, posé dans les préférences par les parcours client à la
/// place de l'ancienne sélection de communes.
///
/// ⚠️ Ce sont les coordonnées du commerçant du décor, pas un lieu quelconque :
/// un point à quelques kilomètres de lui ferait sortir ses promos du rayon, et
/// l'accueil vide accuserait la liste alors que c'est le décor qui viserait à
/// côté (règle #38).
/// ⚠️ `String.fromEnvironment` et non `double.fromEnvironment` : ce dernier
/// n'existe pas en Dart. Les coordonnées voyagent donc en texte et sont
/// converties ici — avec un repli explicite, parce qu'un décor sans point
/// n'aurait aucun sens (règle #29 : le repli est nommé, pas subi).
const String _decorLat =
    String.fromEnvironment('TEST_DECOR_LAT', defaultValue: '34.6714');
const String _decorLng =
    String.fromEnvironment('TEST_DECOR_LNG', defaultValue: '3.2630');
final double decorLatitude = double.parse(_decorLat);
final double decorLongitude = double.parse(_decorLng);

/// Wilaya et commune **de l'agent**, par leur nom, pour la cascade du
/// formulaire de création de commerçant.
///
/// ⚠️ Un agent ne peut créer que dans SES communes : choisir la première venue
/// ferait refuser la création par le serveur, et l'échec accuserait le
/// formulaire. Les noms sont des **données** (ils viennent de la base), pas des
/// libellés traduits — les chercher ne lie pas le parcours à la langue.
const String wilayaNom = String.fromEnvironment('TEST_WILAYA_NOM');
const String communeNom = String.fromEnvironment('TEST_COMMUNE_NOM');

/// Meilleure remise du commerce **telle que le serveur la calcule**
/// (`bestDiscountPercent`, rendu par `GET /promo/map`), déjà formatée comme le
/// marqueur l'affiche — « −87% ».
///
/// ⚠️ Servie, jamais recalculée ici : recalculer, c'est créer un second
/// endroit qui finira par diverger (règle #30).
const String remiseAttendue = String.fromEnvironment('TEST_REMISE');

/// Nom du commerce attendu dans la fiche ouverte depuis le marqueur.
const String commerceNom = String.fromEnvironment('TEST_COMMERCE_NOM');

/// Les cinq compteurs du tableau de bord, **tels que le serveur les sert à ce
/// rôle-là**, séparés par des virgules (`GET /admin/dashboard`).
///
/// ⚠️ Mesurés par le script avec le jeton de CE rôle, jamais recopiés : c'est
/// la seule façon de distinguer « l'écran affiche les chiffres de l'agent » de
/// « l'écran affiche des chiffres ».
const String proStatsAttendues = String.fromEnvironment('TEST_PRO_STATS');

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
/// **même asynchrone et sans rapport avec ce qu'il éprouve**. Une image qui
/// rend 404 suffit donc à faire échouer un parcours qui n'affirme rien sur les
/// images.
///
/// ⚠️ **La raison d'origine n'existe plus, et c'est important de le dire** :
/// `provision-decor.sh` et `seed-demo.sh` annonçaient des `photoKey` auxquelles
/// aucun objet ne correspondait dans MinIO. Depuis le 2026-08-05, les deux
/// **envoient un vrai fichier** et utilisent la clé rendue par le serveur.
///
/// Ce qui reste, et qui justifie de garder ce filtre :
///
///   · les **fonds de carte** viennent d'un serveur de tuiles externe, dont
///     l'échec n'apprend rien sur l'app ;
///   · les données créées **avant** cette correction pointent toujours sur
///     rien, et une base de développement n'est pas remise à zéro.
///
/// ── Ce que ça ne fait PAS ────────────────────────────────────────────────
///
/// Ça n'avale pas « les erreurs » : **uniquement** celles émises par le
/// service de résolution d'images. Toute autre exception continue d'échouer le
/// parcours, par le gestionnaire précédent qu'on rappelle. Un `catch` large
/// ici transformerait le harnais en machine à rassurer (règle #28).
///
/// ⚠️ **Et ce filtre a déjà masqué un vrai symptôme** : tant que le décor
/// mentait, un parcours restait vert sur un appareil dont le cache portait
/// l'image — et rouge sur un appareil neuf. Un filtre est un choix, pas un
/// réglage : quand sa cause disparaît, il faut le redire ou le retirer.
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

/// Fait défiler l'écran jusqu'à ce qu'une condition soit vraie.
///
/// ⚠️ **Un formulaire plus long qu'un écran n'est pas entièrement construit.**
/// Une `ListView` ne bâtit que ce qui est visible (plus une marge) : chercher
/// un champ qui n'a jamais été affiché revient à chercher un widget qui
/// n'existe pas. *Trouvé le 2026-08-05 sur l'inscription commerçant : « Champ
/// de rang 3 absent » alors que le formulaire en compte cinq — les deux
/// derniers étaient sous la ligne de flottaison.*
///
/// ⚠️ **Et défiler change les rangs** : ce qui sort par le haut peut être
/// détruit. Après un défilement, désigner un champ par `.at(3)` ne veut plus
/// rien dire — compter ce qui est visible, ou viser `.last`.
Future<void> defilerJusquaVrai(
  WidgetTester tester,
  bool Function() condition, {
  required String raison,
  int essais = 12,
}) async {
  for (var i = 0; i < essais; i++) {
    if (condition()) return;
    // ⚠️ Rien à faire défiler tant que l'écran n'est pas bâti : `tester.drag`
    // rendait « Bad state: No element » quand l'app démarrait encore. On pompe
    // alors, ce qui fait de ce helper une attente doublée d'un défilement —
    // sans jamais transformer une absence en succès, l'échec tombe au bout.
    final zones = find.byType(Scrollable);
    if (zones.evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 300));
      continue;
    }
    await tester.drag(zones.last, const Offset(0, -280));
    await tester.pump(const Duration(milliseconds: 250));
  }
  if (condition()) return;
  fail('$raison — non atteint après $essais défilements.\n'
      'à l\'écran : ${textesRendus()}');
}

/// Fait défiler jusqu'à ce qu'un widget PRÉCIS soit visible.
///
/// Préférer cette forme à [defilerJusquaVrai] quand on sait ce qu'on cherche :
/// `scrollUntilVisible` s'arrête dès que la cible est là et gère le
/// défilement lui-même, là où un glissement à l'aveugle peut ne pas prendre.
/// *Le rejeu d'ensemble du 2026-08-05 a échoué là-dessus : le bouton de
/// création restait hors d'atteinte après douze glissements, sur un écran qui
/// était passé la veille.*
Future<void> defilerJusqua(
  WidgetTester tester,
  Finder cible, {
  required String raison,
}) async {
  if (cible.evaluate().isNotEmpty) return;
  try {
    await tester.scrollUntilVisible(
      cible,
      250,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
  } catch (_) {
    fail('$raison — non atteint après défilement.\n'
        'à l\'écran : ${textesRendus()}');
  }
}

/// Tape un élément après s'être assuré qu'il est visible.
///
/// ⚠️ Taper l'icône ne suffit pas : un bandeau peut la recouvrir, ou l'écran
/// peut ne pas avoir fini de se reconstruire. Le tap part alors dans le vide,
/// et l'assertion suivante attend trente secondes avant d'accuser l'écran.
/// ⚠️ **La cible peut disparaître ENTRE la vérification et le tap.** Ouvrir le
/// clavier, faire défiler, afficher un aperçu de photo : chacun relayoute
/// l'écran, et ce qui sort de la zone construite est détruit. `tester.tap`
/// rendait alors « Bad state: No element » — une erreur Dart qui ne dit ni
/// quoi, ni où. *Trouvé deux fois le 2026-08-05, sur l'inscription commerçant
/// puis sur la création par l'agent, les deux fois juste après une saisie.*
///
/// D'où trois tentatives, et un échec qui **nomme la cible et montre l'écran**.
/// Le réessai ne masque rien : si la cible ne revient pas, on échoue.
Future<void> taper(WidgetTester tester, Finder cible) async {
  for (var essai = 0; essai < 3; essai++) {
    if (cible.evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 300));
      continue;
    }
    await tester.ensureVisible(cible.first);
    await tester.pump(const Duration(milliseconds: 200));
    // Revérifié après `ensureVisible` : c'est précisément lui qui fait défiler,
    // donc lui qui peut faire sortir la cible de l'autre côté.
    if (cible.evaluate().isEmpty) continue;
    await tester.tap(cible.first);
    await tester.pump(const Duration(milliseconds: 600));
    return;
  }
  fail('rien à taper pour $cible après 3 tentatives.\n'
      'à l\'écran : ${textesRendus()}');
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
