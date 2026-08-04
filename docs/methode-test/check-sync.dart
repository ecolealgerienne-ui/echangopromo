/// Vérificateur de synchronisation serveur ↔ app — squelette (étage 1).
///
/// Compare un **registre serveur** (enum TypeScript) aux **tables de
/// traduction** de l'application, une par langue. Les ensembles de clés doivent
/// être strictement identiques, doublons compris.
///
/// ── Pourquoi ce contrôle existe ──────────────────────────────────────────
///
/// C'est une désynchronisation **totalement silencieuse** (mode M5) : rien ne
/// compile en rouge, rien ne lève. Un code ajouté côté serveur et absent d'une
/// table fait afficher le message serveur brut — toujours dans UNE langue — à
/// la place du texte localisé, sans une erreur d'aucun côté pour le signaler.
///
/// ── Usage ────────────────────────────────────────────────────────────────
///
///   dart run check-sync.dart --self-test   # d'abord, et c'est bloquant
///   dart run check-sync.dart               # le contrôle
///   dart run check-sync.dart --mutation    # mode d'emploi de la mutation
///
/// ⚠️ **Ce vérificateur doit être prouvé par mutation du VRAI fichier**, pas
/// seulement par son auto-test (mode M1). Les cas fabriqués n'ont pas la
/// structure du vrai fichier : c'est une mutation réelle qui a trouvé, sur le
/// projet d'origine, qu'une ancre `'… _ar'` matchait aussi `_arabe` — donc que
/// renommer la table faisait repartir le contrôle en silence sur une table qui
/// ne portait plus le nom attendu.

import 'dart:io';

// ─────────────────────────────────────────────────────────────────────────────
// À ADAPTER — les fichiers comparés
// ─────────────────────────────────────────────────────────────────────────────

const sourceServeur = 'apps/backend/src/common/errors/error-code.enum.ts';
const nomEnumServeur = 'ErrorCode';

const tablesApp = <String, String>{
  'fr': 'apps/mobile/lib/features/shared/errors/error_messages_fr.dart',
  'en': 'apps/mobile/lib/features/shared/errors/error_messages_en.dart',
  'ar': 'apps/mobile/lib/features/shared/errors/error_messages_ar.dart',
};

/// Les codes délibérément absents des tables, épinglés AVEC leur raison.
///
/// ⚠️ Ne jamais y ajouter une entrée pour faire passer le contrôle. Une
/// exclusion anonyme est indiscernable d'un oubli — c'est exactement ce que la
/// méthode reproche à une absence non écrite.
const exclusions = <String, String>{
  'VALIDATION_ERROR': 'message intrinsèquement dynamique, composé côté serveur',
  // À ADAPTER
};

/// Les codes que l'APPLICATION émet seule, épinglés AVEC leur origine.
///
/// Ils sont légitimement présents dans les tables et absents de l'enum serveur
/// — un échec réseau ou un refus de permission n'a jamais de réponse HTTP à
/// porter un code. Sans cette liste, le contrôle les signalerait « en trop » à
/// chaque passage, et un contrôle qui crie au loup finit désactivé.
const codesClientSeuls = <String, String>{
  'NETWORK_ERROR': 'apps/mobile/lib/data/api/api_exception.dart',
  // À ADAPTER
};

// ─────────────────────────────────────────────────────────────────────────────
// Extraction
// ─────────────────────────────────────────────────────────────────────────────

/// Les membres d'un enum TypeScript `export enum X { A = 'a', B = 'b' }`.
///
/// ⚠️ On lit les **membres**, pas les valeurs : c'est le nom qui sert de clé
/// des deux côtés. Les commentaires sont retirés d'abord, sans quoi un membre
/// mis en commentaire serait compté comme présent — mode de panne constaté.
Set<String> membresEnum(String source, String nom) {
  final sansCommentaires = source
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .replaceAll(RegExp(r'//[^\n]*'), '');

  final bloc = RegExp('enum\\s+$nom\\s*\\{([\\s\\S]*?)\\}').firstMatch(sansCommentaires);
  if (bloc == null) return <String>{};

  // ⚠️ **Les valeurs sont retirées avant de chercher les membres.** Sans ça, un
  // membre dont la valeur contient des majuscules ('NOT_FOUND') serait compté
  // deux fois — et un `enum E { A = 'a', B = 'b' }` sur UNE ligne ne rendrait
  // que son premier membre si l'on s'ancrait en début de ligne. Défaut trouvé
  // par l'auto-test, pas par la relecture (mode M1).
  final sansValeurs = bloc
      .group(1)!
      .replaceAll(RegExp(r"'[^']*'"), '')
      .replaceAll(RegExp(r'"[^"]*"'), '');

  return RegExp(r'([A-Z][A-Z0-9_]*)\s*(?==|,|$)', multiLine: true)
      .allMatches(sansValeurs)
      .map((m) => m.group(1)!)
      .toSet();
}

/// Les clés d'une table Dart, SANS présumer de leur forme.
///
/// ⚠️ **Le piège documenté.** Une version qui filtrerait sur une forme
/// particulière (`domaine.motif`, `MAJUSCULES_AVEC_UNDERSCORES`…) ne verrait
/// pas les clés d'une autre forme, signalerait un manque inexistant, et
/// l'entrée ajoutée pour le satisfaire créerait un doublon. **Un vérificateur
/// qui ne voit pas tout ne rassure pas, il déplace l'erreur.**
///
/// On reconnaît donc toute chaîne littérale suivie d'un `:` — la forme d'une
/// clé de map Dart, quelle que soit la convention de nommage.
List<String> clesTable(String source) {
  final sansCommentaires = source
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .replaceAll(RegExp(r'//[^\n]*'), '');

  return RegExp("""['"]([^'"]+)['"]\\s*:""")
      .allMatches(sansCommentaires)
      .map((m) => m.group(1)!)
      .toList(); // liste, pas set : les doublons sont une information
}

List<String> doublons(List<String> cles) {
  final vus = <String>{};
  final deuxFois = <String>[];
  for (final c in cles) {
    if (!vus.add(c)) deuxFois.add(c);
  }
  return deuxFois;
}

// ─────────────────────────────────────────────────────────────────────────────
// Auto-test — autant de cas de refus que de cas qui passent (mode M1)
// ─────────────────────────────────────────────────────────────────────────────

int _ok = 0;
final _echecs = <String>[];

void _attendu(String libelle, Object obtenu, Object attendu) {
  if (obtenu.toString() == attendu.toString()) {
    _ok++;
  } else {
    _echecs.add('$libelle — attendu $attendu, obtenu $obtenu');
  }
}

bool selfTest() {
  // ── Cas qui doivent PASSER ────────────────────────────────────────────────
  _attendu('enum simple',
      membresEnum("export enum E { A = 'a', B = 'b' }", 'E').toList()..sort(),
      ['A', 'B']);
  _attendu('enum multi-lignes',
      membresEnum("enum E {\n  A = 'a',\n  LONG_NOM = 'x',\n}", 'E').toList()..sort(),
      ['A', 'LONG_NOM']);
  _attendu('clés en snake_case',
      clesTable("{'auth_token_missing': 'x'}"), ['auth_token_missing']);
  _attendu('clés pointées',
      clesTable("{'order.not_found': 'x'}"), ['order.not_found']);
  _attendu('clé courte sans point ni underscore',
      clesTable("{'not_found': 'x', 'x': 'y'}"), ['not_found', 'x']);
  _attendu('guillemets doubles',
      clesTable('{"A": "x"}'), ['A']);
  _attendu('doublon détecté',
      doublons(['a', 'b', 'a']), ['a']);

  // ── Cas de REFUS : le vérificateur doit NE PAS voir ces entrées ───────────
  _attendu('membre en commentaire ligne ignoré',
      membresEnum("enum E {\n  A = 'a',\n  // B = 'b',\n}", 'E').toList(), ['A']);
  _attendu('membre en bloc commentaire ignoré',
      membresEnum("enum E {\n  A = 'a',\n  /* B = 'b', */\n}", 'E').toList(), ['A']);
  _attendu('mauvais nom d’enum → rien',
      membresEnum("enum Autre { A = 'a' }", 'E').toList(), []);
  _attendu('clé en commentaire ignorée',
      clesTable("// {'fantome': 'x'}\n{'vrai': 'y'}"), ['vrai']);
  _attendu('valeur avec deux-points n’est pas une clé',
      clesTable("{'a': 'http://x'}"), ['a']);
  _attendu('table vide → rien',
      clesTable('{}'), []);

  const casRefus = 6;
  final total = _ok + _echecs.length;
  stdout.writeln('auto-test : $total cas, dont $casRefus refus');
  for (final e in _echecs) {
    stdout.writeln('  ❌ $e');
  }
  stdout.writeln('  $_ok/$total');
  return _echecs.isEmpty;
}

void modeMutation() {
  stdout.writeln('''
── Prouver ce vérificateur par MUTATION du vrai fichier ──

L'auto-test ne porte que sur des cas fabriqués : ils n'ont pas la structure du
vrai fichier. Faire les trois mutations suivantes, une par une, et vérifier que
le contrôle REFUSE à chaque fois :

  1. Ajouter un membre bidon à l'enum serveur      → doit signaler 3 manques
  2. Retirer une clé d'UNE seule table de langue   → doit signaler 1 manque
  3. Dupliquer une clé dans une table              → doit signaler 1 doublon

Puis renommer un fichier de table (ex. _ar.dart → _arabe.dart) : le contrôle
doit ÉCHOUER sur le fichier introuvable, jamais conclure à l'accord.
Un contrôle qui conclut à l'accord quand il ne trouve pas sa source est le
mode de panne le plus dangereux de cette famille.
''');
}

// ─────────────────────────────────────────────────────────────────────────────

void main(List<String> args) {
  if (args.contains('--self-test')) {
    exit(selfTest() ? 0 : 1);
  }
  if (args.contains('--mutation')) {
    modeMutation();
    return;
  }

  // ⚠️ Une source introuvable ARRÊTE le contrôle. Ne jamais rendre un ensemble
  // vide : « aucun écart » sur une source absente est un faux vert (mode M3).
  String lire(String chemin) {
    final f = File(chemin);
    if (!f.existsSync()) {
      stderr.writeln('❌ introuvable : $chemin');
      stderr.writeln('   L\'absence de verdict n\'est pas un verdict.');
      exit(2);
    }
    return f.readAsStringSync();
  }

  final serveur = membresEnum(lire(sourceServeur), nomEnumServeur);
  if (serveur.isEmpty) {
    stderr.writeln('❌ enum $nomEnumServeur vide ou non reconnue dans $sourceServeur');
    exit(2);
  }

  final attendus = serveur.difference(exclusions.keys.toSet());
  var problemes = 0;

  stdout.writeln('serveur : ${serveur.length} codes '
      '(${exclusions.length} exclusion(s) épinglée(s)) → ${attendus.length} attendus\n');

  tablesApp.forEach((langue, chemin) {
    final cles = clesTable(lire(chemin));
    final ensemble = cles.toSet();

    final manquants = attendus.difference(ensemble).toList()..sort();
    final enTrop = ensemble
        .difference(serveur)
        .difference(codesClientSeuls.keys.toSet())
        .toList()
      ..sort();
    final deuxFois = doublons(cles);

    if (manquants.isEmpty && enTrop.isEmpty && deuxFois.isEmpty) {
      stdout.writeln('  ✅ $langue — ${ensemble.length} clés, accord complet');
      return;
    }
    problemes++;
    stdout.writeln('  ❌ $langue');
    for (final c in manquants) {
      stdout.writeln('       manque   $c  (servi par le serveur, jamais traduit)');
    }
    for (final c in enTrop) {
      stdout.writeln('       en trop  $c  (traduit, mais le serveur ne l\'émet pas)');
    }
    for (final c in deuxFois) {
      stdout.writeln('       doublon  $c');
    }
  });

  stdout.writeln();
  if (problemes > 0) {
    stdout.writeln('❌ $problemes table(s) désynchronisée(s).');
    exit(1);
  }
  stdout.writeln('✅ les ${tablesApp.length} tables sont d\'accord avec le serveur.');
}
