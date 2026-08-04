/// Lance les trois vérificateurs de synchronisation serveur ↔ app, et dit
/// lesquels passent.
///
/// ── Pourquoi un lanceur ──────────────────────────────────────────────────
///
/// Trois contrôles lancés à la main sont trois contrôles qu'on oublie. Celui-ci
/// est le point d'entrée unique de l'étage 1 (`docs/METHODE_TEST.md`) : statique,
/// instantané, sans base ni émulateur — donc le seul lot qui pourrait tourner à
/// chaque commit.
///
/// ⚠️ **Il ne s'arrête pas au premier échec, délibérément.** Sortir tôt
/// masquerait l'état des suivants — et c'est justement ce qu'on veut savoir en
/// rejouant une suite.
///
/// ⚠️ **L'auto-test de chaque vérificateur tourne d'abord, et son échec est
/// bloquant pour ce vérificateur.** Un contrôle dont on n'a pas vérifié qu'il
/// sait dire non ne prouve rien de ce qu'il déclare ensuite.
///
/// ── Usage ────────────────────────────────────────────────────────────────
///
///   cd apps/mobile && dart run tool/check_all.dart
library;

import 'dart:convert';
import 'dart:io';

const _verificateurs = <String, String>{
  'codes d\'erreur': 'tool/check_error_codes.dart',
  'enums miroirs': 'tool/check_enums.dart',
  'bornes de validation': 'tool/check_server_rules.dart',
  'thème et couleurs': 'tool/check_theme.dart',
};

Future<int> _lancer(String script, List<String> args) async {
  // ⚠️ Encodage forcé en UTF-8 : sans ça, Windows décode la sortie des
  // sous-processus dans la page de codes système et les accents comme les
  // symboles ✅/❌ ressortent en mojibake — un rapport illisible se cesse
  // d'être lu.
  final r = await Process.run('dart', ['run', script, ...args],
      runInShell: true, stdoutEncoding: utf8, stderrEncoding: utf8);
  final sortie = '${r.stdout}${r.stderr}'.trimRight();
  if (sortie.isNotEmpty) {
    stdout.writeln(sortie.split('\n').map((l) => '   $l').join('\n'));
  }
  return r.exitCode;
}

Future<void> main() async {
  final resultats = <String, String>{};

  for (final e in _verificateurs.entries) {
    stdout.writeln('\n════ ${e.key} ════');

    final auto = await _lancer(e.value, ['--self-test']);
    if (auto != 0) {
      // ⚠️ On n'exécute PAS le contrôle réel : son verdict ne vaudrait rien.
      resultats[e.key] = '❌ auto-test en échec — verdict non calculé';
      continue;
    }

    final code = await _lancer(e.value, []);
    resultats[e.key] = code == 0
        ? '✅'
        : (code == 2 ? '❌ source introuvable (code 2)' : '❌ désynchronisé');
  }

  stdout.writeln('\n════════════════════════════════════════════════');
  var ko = 0;
  resultats.forEach((nom, verdict) {
    stdout.writeln('  ${verdict.padRight(34)} $nom');
    if (verdict.startsWith('❌')) ko++;
  });
  stdout.writeln('════════════════════════════════════════════════');
  stdout.writeln('  ${_verificateurs.length - ko} passés, $ko en échec');
  exit(ko == 0 ? 0 : 1);
}
