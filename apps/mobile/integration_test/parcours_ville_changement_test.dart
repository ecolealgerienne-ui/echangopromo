/// **Parcours client — changer de ville depuis la carte** (scénario 2).
///
/// ⚠️ **Fichier séparé, et c'est nécessaire.** Ces trois tests tenaient d'abord
/// dans un seul, et le troisième échouait en affichant la proposition du
/// PREMIER point (« Vous êtes ici… ») alors qu'un point était posé avant le
/// démarrage : l'app ne le voyait pas. `SharedPreferences` est un singleton de
/// **processus**, et `flutter drive` n'en lance qu'un pour tout le fichier —
/// l'état du test précédent déteint sur le suivant.
///
/// C'est la contrainte que `test-parcours-ecran.sh` énonce déjà en tête :
/// *« un `flutter drive` par parcours, et c'est nécessaire »*. Elle y était
/// justifiée par `splashShownThisLaunch` ; elle vaut tout autant pour les
/// préférences.
///
/// Le reste — ce que ce parcours éprouve, et ce qu'il ne peut pas atteindre —
/// est écrit sur le test lui-même.
library;

import 'package:echango_promo/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

/// Nom d'un commerce de la ville de départ — servi par le script, qui le tient
/// du serveur. Recopier un libellé ici ferait échouer le parcours le jour où le
/// décor change de nom.
const String villeCommerce = String.fromEnvironment('TEST_VILLE_COMMERCE');
const String villeLat = String.fromEnvironment('TEST_VILLE_LAT');
const String villeLng = String.fromEnvironment('TEST_VILLE_LNG');

/// La proposition est-elle affichée ?
///
/// ⚠️ **`find.byType(FilledButton)` ne l'identifie PAS**, et c'est ce qui a fait
/// échouer ce parcours deux fois : le bandeau d'invitation à activer la
/// localisation en porte un aussi — et il s'affiche précisément parce que ces
/// parcours tournent sans GPS. Le témoin négatif accusait donc la proposition
/// pour un bouton qui n'était pas le sien.
///
/// On vise le TEXTE du bandeau, en acceptant les deux langues que l'émulateur
/// peut servir. ⚠️ Un appareil en arabe ferait échouer cette reconnaissance —
/// limite dite plutôt que découverte.
bool propositionVisible() => textesRendus().any((t) =>
    t.contains('comme ville par défaut') ||
    t.contains('as your default city') ||
    t.contains('default city?'));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// ── Scénario 2 : explorer une autre ville et l'adopter ───────────────────
  ///
  /// Le parcours d'un vrai client : il voit sa liste, va sur la carte,
  /// s'éloigne, se voit proposer la ville qu'il regarde, l'accepte — et sa
  /// liste a changé.
  ///
  /// ⚠️ **Ce test ne peut pas atteindre une VILLE en glissant.** Hassi Bahbah
  /// est à 50 km, soit ~3 200 px au zoom d'ouverture : une dizaine de gestes,
  /// et un atterrissage au mètre près qu'aucun test ne peut viser. Il éprouve
  /// donc ce qui est à sa portée et qui porte tout le mécanisme : franchir le
  /// rayon déclenche la proposition, l'accepter change le point, et **la liste
  /// suit**.
  ///
  /// La moitié positive — « on voit les promos de la nouvelle ville » — est
  /// couverte par le premier test de ce fichier, qui part d'un point déjà posé
  /// sur Hassi Bahbah. Les deux ensemble ferment la boucle : changer de point
  /// change la liste, et un point posé sert bien sa ville.
  testWidgets('explorer au-delà du rayon fait proposer la ville regardée',
      (tester) async {
    await reinitialiserAppareil();
    ignorerErreursDeChargementDImage();
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('onboarding_completed', true);
    // On part de la ville du décor — celle dont on connaît un commerce.
    prefs.setDouble('client_position_lat', double.parse(villeLat));
    prefs.setDouble('client_position_lng', double.parse(villeLng));
    prefs.setString('client_position_consent_version', 'geo-2026-08-12');

    app.main();
    await tester.pump(const Duration(seconds: 2));

    // ── 1. La liste porte bien un commerce de la ville de départ ───────────
    //
    // Établi AVANT tout geste : sans ça, la disparition constatée à la fin ne
    // prouverait rien — elle serait vraie pendant n'importe quel chargement.
    await pomperJusquaVrai(
      tester,
      () => textesRendus().any((t) => t.contains(villeCommerce)),
      raison: 'la liste ne porte pas « $villeCommerce » au départ : le point '
          'enregistré n’a pas été pris en compte, et la suite ne prouverait rien',
      limite: const Duration(seconds: 45),
    );

    // ── 2. Sur la carte, rien ne doit être proposé : on est chez soi ────────
    await taper(tester, find.byIcon(Icons.map_outlined));
    await tester.pump(const Duration(seconds: 3));

    // ── ⚠️ Écarter d'abord l'invitation à la localisation ──────────────────
    //
    // Un seul bandeau s'affiche à la fois, et l'invitation passe devant la
    // proposition de ville : deux sollicitations superposées se lisent comme du
    // harcèlement, et Apple l'a refusé le 2026-08-05 (5.1.1(iv)).
    //
    // ⚠️ **Conséquence produit, mesurée ici** : tant que le client n'a pas
    // écarté l'invitation, il ne verra JAMAIS la proposition de changer de
    // ville. Sur un appareil sans localisation, elle reste affichée
    // indéfiniment — donc la proposition est inatteignable. Ce parcours a
    // échoué là-dessus, en annonçant « aucune proposition » alors que la carte
    // s'était bien déplacée de 6,2 km (sonde : centre 35.0774 → 35.1336).
    //
    // Le parcours fait donc ce que ferait l'utilisateur : il ferme
    // l'invitation, puis explore.
    if (find.byIcon(Icons.close).evaluate().isNotEmpty) {
      await taper(tester, find.byIcon(Icons.close));
      await tester.pump(const Duration(seconds: 2));
    }
    expect(
      propositionVisible(),
      isFalse,
      reason: 'une proposition de changer de ville s’affiche alors que le '
          'client regarde SA ville — elle deviendrait du harcèlement',
    );

    // ── 3. S'éloigner au-delà du rayon ─────────────────────────────────────
    //
    // ⚠️ 400 px au zoom d'ouverture (13) valent ~6,3 km à cette latitude, donc
    // au-delà des 5 km du rayon servi. Le nombre n'est pas magique : il est
    // dérivé de la résolution de la projection Web Mercator (~15,7 m/px ici) et
    // du rayon que le serveur annonce. En dessous du rayon, rien ne doit être
    // proposé — c'est ce que le § 2 vient de vérifier.
    // ⚠️ `timedDrag` et non `drag` : `flutter_map` suit le doigt par les
    // événements de MOUVEMENT intermédiaires. Un `drag` synthétise un
    // appui-déplacement-relâchement quasi instantané, et la carte ne bouge
    // PAS — mesuré par sonde le 2026-08-13 : le centre restait rivé au point
    // de départ sur toutes les constructions, donc l'écart valait zéro et
    // aucune proposition ne pouvait naître.
    await tester.timedDrag(
      find.byType(FlutterMap),
      const Offset(0, 400),
      const Duration(milliseconds: 800),
    );
    await tester.pump(const Duration(seconds: 3));

    // ── 4. La proposition apparaît ─────────────────────────────────────────
    await pomperJusquaVrai(
      tester,
      propositionVisible,
      raison: 'après s’être éloigné de plus de 5 km, aucune proposition de '
          'prendre cette ville — le client n’a aucun moyen de découvrir le geste',
      limite: const Duration(seconds: 30),
    );
    // Le bouton d'acceptation du bandeau — le dernier `FilledButton` de
    // l'écran, l'invitation à la localisation venant avant lui dans l'arbre.
    await taper(tester, find.byType(FilledButton).last);

    // Le consentement, dans sa boîte : enregistrer un point est un envoi de
    // donnée, il ne se fait pas sans un oui explicite.
    await pomperJusqua(
      tester,
      find.byType(AlertDialog),
      raison: 'la proposition n’a pas demandé de consentement avant '
          'd’enregistrer le point',
    );
    await taper(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ),
    );

    // ── 5. Le point a changé, et la liste a suivi ──────────────────────────
    await pomperJusquaVrai(
      tester,
      () {
        final lat = prefs.getDouble('client_position_lat');
        return lat != null && (lat - double.parse(villeLat)).abs() > 0.02;
      },
      raison: 'le point enregistré n’a pas bougé après avoir accepté la '
          'proposition — le geste n’a rien fait',
      limite: const Duration(seconds: 30),
    );

    // ⚠️ L'accueil, c'est `home_outlined` — pas `list_outlined`, qui
    // n'existe pas dans cette barre. Vérifié dans
    // `promo_list_screen.dart`, et non deviné.
    await taper(tester, find.byIcon(Icons.home_outlined));
    await pomperJusquaVrai(
      tester,
      () => !textesRendus().any((t) => t.contains(villeCommerce)),
      raison: 'la liste montre toujours « $villeCommerce » alors que le point '
          'a changé de plus de 5 km : elle ne suit pas le point du client',
      limite: const Duration(seconds: 45),
    );
  });
}
