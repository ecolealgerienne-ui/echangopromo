import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

/// Lanceur du parcours de **profilage** — distinct de `integration_test.dart`.
///
/// ⚠️ Deux lanceurs, et c'est nécessaire : `integrationDriver()` sans rappel
/// **jette** les données de performance renvoyées par l'appareil. Le parcours
/// pourrait mesurer parfaitement des milliers d'images et rien n'en sortirait —
/// un profilage silencieusement vide, qui se lit comme un profilage réussi.
///
/// Ce lanceur les écrit sur disque, où un banc peut les juger.
Future<void> main() => integrationDriver(
      responseDataCallback: (Map<String, dynamic>? donnees) async {
        if (donnees == null) {
          // ⚠️ Dit, jamais tu : un fichier absent serait indiscernable d'un
          // parcours qui n'a rien mesuré.
          stderr.writeln(
              '[PERF] aucune donnée renvoyée par l’appareil — le parcours '
              'n’a pas appelé watchPerformance, ou il a échoué avant.');
          return;
        }
        final fichier = File('build/perf_carte.json');
        await fichier.parent.create(recursive: true);
        await fichier.writeAsString(
            const JsonEncoder.withIndent('  ').convert(donnees));
        stdout.writeln('[PERF] écrit dans ${fichier.path}');
      },
    );
