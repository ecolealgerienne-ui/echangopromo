/// **Profilage de la carte — les temps d'image, pas les millisecondes réseau.**
///
/// ── Pourquoi la carte, et elle seule ────────────────────────────────────────
///
/// `banc_perf` mesure le serveur : 12 à 17 ms en p95. Rien à optimiser de ce
/// côté aujourd'hui. La fluidité que le client ressent se joue donc ailleurs, et
/// la carte est le seul écran qui la mette réellement à l'épreuve : des tuiles
/// chargées en continu, des marqueurs regroupés à chaque changement de zoom, et
/// un geste qui doit suivre le doigt image par image.
///
/// ── ⚠️ Ce parcours n'a de sens qu'en mode PROFILE ───────────────────────────
///
/// En `debug`, le code Dart est interprété et les assertions tournent : les
/// temps d'image y sont deux à dix fois pires qu'en production, sans aucun
/// rapport avec ce que vit un utilisateur. Un profilage en debug ne mesure pas
/// le produit, il mesure le mode debug — et il conduirait à « optimiser » du
/// code qui n'a rien.
///
/// `./scripts/test-perf-carte.sh` impose `--profile` ; ce fichier ne peut pas
/// le vérifier lui-même, et c'est écrit ici pour que personne ne le lance à la
/// main en croyant mesurer quelque chose.
///
/// ── Ce que `watchPerformance` capture, et ce qu'il ne capture pas ───────────
///
/// Il enregistre le temps de **construction** (côté Dart, l'arbre de widgets)
/// et le temps de **rastérisation** (côté GPU, le dessin réel) de chaque image.
/// Les deux comptent et ne se remplacent pas : une construction rapide dont la
/// rastérisation traîne donne exactement le même à-coup à l'écran.
///
/// Il ne capture ni le temps de chargement des tuiles (réseau), ni le décodage
/// des photos — ces deux-là ne bloquent pas le fil d'interface et n'apparaissent
/// pas dans les temps d'image. Les mesurer demanderait autre chose ; le taire
/// ferait croire que ce parcours couvre tout le ressenti.
///
/// ── ⚠️ Sans GPS, et c'est délibéré ──────────────────────────────────────────
///
/// Le GPS de cet émulateur est figé sur Mountain View. Un relevé actif
/// recentrerait la carte à mi-parcours et on mesurerait un recentrage subi,
/// pas un panoramique volontaire. Le point est donc posé avant le démarrage.
library;

import 'package:echango_promo/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

const String villeLat = String.fromEnvironment('TEST_VILLE_LAT');
const String villeLng = String.fromEnvironment('TEST_VILLE_LNG');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('la carte reste fluide en panoramique et au changement de zoom',
      (tester) async {
    exigerIdentifiants({
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

    await pomperJusqua(
      tester,
      find.byIcon(Icons.map_outlined),
      raison: 'la barre d’onglets client n’est pas apparue',
    );
    await taper(tester, find.byIcon(Icons.map_outlined));

    // ⚠️ On attend que la carte EXISTE avant de commencer à mesurer : inclure
    // sa première construction mélangerait un coût d'ouverture, payé une fois,
    // avec le coût d'un geste, payé à chaque fois. Les deux sont réels, mais
    // les moyenner ne décrit ni l'un ni l'autre.
    await pomperJusqua(
      tester,
      find.byType(FlutterMap),
      raison: 'la carte ne s’est pas affichée',
      limite: const Duration(seconds: 45),
    );
    await tester.pump(const Duration(seconds: 3));

    final carte = find.byType(FlutterMap);

    // ── La mesure ────────────────────────────────────────────────────────────
    //
    // ⚠️ `timedDrag` et non `drag` : `flutter_map` suit le doigt par les
    // événements de MOUVEMENT intermédiaires. Un `drag` synthétise un geste
    // quasi instantané — la carte ne bouge pas, et on mesurerait une scène
    // immobile en croyant mesurer un panoramique (mesuré le 2026-08-13, ça a
    // fait échouer un autre parcours pendant une demi-journée).
    await binding.watchPerformance(() async {
      for (var tour = 0; tour < 3; tour++) {
        for (final direction in const [
          Offset(0, 260),
          Offset(0, -260),
          Offset(240, 0),
          Offset(-240, 0),
        ]) {
          await tester.timedDrag(
            carte,
            direction,
            const Duration(milliseconds: 700),
          );
          await tester.pump(const Duration(milliseconds: 400));
        }

        // Le changement de zoom recalcule TOUS les regroupements de marqueurs :
        // c'est l'opération la plus lourde de cet écran, et celle qu'un
        // panoramique seul ne déclenche jamais.
        for (final icone in const [Icons.remove, Icons.add]) {
          final bouton = find.byIcon(icone);
          if (bouton.evaluate().isNotEmpty) {
            await tester.tap(bouton.first, warnIfMissed: false);
            await tester.pump(const Duration(milliseconds: 600));
          }
        }
      }
    }, reportKey: 'carte');
  });
}
