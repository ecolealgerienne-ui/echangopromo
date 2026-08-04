/// Vérifie que le registre de codes d'erreur du backend et les trois tables de
/// traduction de l'application restent d'accord (CLAUDE.md règle #26).
///
/// ── Pourquoi ce contrôle existe ──────────────────────────────────────────
///
/// La désynchronisation est **totalement silencieuse** : rien ne compile en
/// rouge, rien ne lève. Un code ajouté côté serveur et absent d'une table fait
/// afficher le message backend brut — **toujours en français** — à la place du
/// texte localisé, y compris pour un utilisateur arabophone
/// (`ApiException.displayMessage` : `messages[code] ?? message`).
///
/// ── ⚠️ Ce que ce fichier remplace, et c'est le point ─────────────────────
///
/// Les exclusions volontaires étaient jusqu'ici décrites dans le **commentaire
/// d'en-tête** de `error_messages_fr.dart`. Un commentaire ne peut pas
/// échouer, et surtout aucun outil ne peut le lire : le 2026-08-04, un
/// vérificateur les a donc toutes signalées comme des défauts. La liste vit
/// désormais **ici**, en donnée, chaque entrée portant sa raison — et le
/// commentaire de `error_messages_fr.dart` peut pointer vers ce fichier.
///
/// ── Usage ────────────────────────────────────────────────────────────────
///
///   cd apps/mobile
///   dart run tool/check_error_codes.dart --self-test   # bloquant
///   dart run tool/check_error_codes.dart               # le contrôle
///   dart run tool/check_error_codes.dart --mutation    # comment l'éprouver
library;

import 'dart:io';

// ─────────────────────────────────────────────────────────────────────────────
// Ce qui est comparé
// ─────────────────────────────────────────────────────────────────────────────

const _sourceServeur = 'apps/backend/src/common/errors/error-code.enum.ts';
const _nomEnum = 'ErrorCode';

const _tablesApp = <String, String>{
  'fr': 'apps/mobile/lib/features/shared/errors/error_messages_fr.dart',
  'en': 'apps/mobile/lib/features/shared/errors/error_messages_en.dart',
  'ar': 'apps/mobile/lib/features/shared/errors/error_messages_ar.dart',
};

/// Codes du serveur **volontairement** absents des tables, avec leur raison.
///
/// ⚠️ **Ne jamais y ajouter une entrée pour faire passer le contrôle.** Une
/// exclusion sans raison est indiscernable d'un oubli — c'est précisément le
/// problème que ce fichier existe pour résoudre.
///
/// ⚠️ **Le prix de ces exclusions doit rester conscient** : un code non mappé
/// retombe sur le message backend, qui est **toujours en français**. Un
/// utilisateur arabophone ou anglophone voit donc du français. Le jour où ce
/// prix devient inacceptable, la sortie n'est pas d'ajouter un mapping statique
/// (il perdrait la valeur interpolée) mais de faire porter les paramètres par
/// la réponse serveur pour que l'app compose la phrase elle-même.
const _exclusions = <String, String>{
  'VALIDATION_ERROR':
      'message par champ, composé dynamiquement côté serveur',
  'PROMO_DATE_FIN_EXCEEDS_MAX':
      'le message interpole la durée maximale — un mapping statique la perdrait',
  'PROMO_ACTIVE_CAP_REACHED':
      'le message interpole le plafond — idem',
  'PROMO_DAILY_CREATION_CAP_REACHED':
      'le message interpole le plafond quotidien — idem',
  'PROMO_REPUBLISH_TOO_SOON':
      'le message interpole le délai restant — idem',
  // ⚠️ HIGHLIGHT_CAP_REACHED n'est PAS ici, délibérément. Son message
  // interpole lui aussi une valeur (`limité à ${HIGHLIGHT_MAX_SLIDES}`), il
  // appartient donc probablement à la même famille — mais il n'a jamais été
  // documenté comme exclusion. L'inscrire ici sans décision serait exactement
  // « ajouter une entrée pour faire passer le contrôle ». Il doit donc être
  // signalé jusqu'à ce que quelqu'un tranche.
};

/// Codes que l'**application** émet seule, avec leur origine.
///
/// Légitimement présents dans les tables et absents de l'enum serveur : un
/// échec réseau n'a pas de réponse HTTP à porter un code.
const _codesClientSeuls = <String, String>{
  'NETWORK_ERROR': 'apps/mobile/lib/data/api/api_exception.dart',
};

// ─────────────────────────────────────────────────────────────────────────────
// Extraction
// ─────────────────────────────────────────────────────────────────────────────

String _sansCommentaires(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

/// Les membres d'un enum TypeScript.
///
/// ⚠️ Les valeurs sont retirées avant de chercher les membres : sans ça, un
/// membre dont la valeur reprend le nom serait compté deux fois, et un enum
/// déclaré sur une seule ligne ne rendrait que son premier membre.
Set<String> membresEnum(String source, String nom) {
  final bloc =
      RegExp('enum\\s+$nom\\s*\\{([\\s\\S]*?)\\}').firstMatch(_sansCommentaires(source));
  if (bloc == null) return <String>{};

  final sansValeurs = bloc
      .group(1)!
      .replaceAll(RegExp(r"'[^']*'"), '')
      .replaceAll(RegExp(r'"[^"]*"'), '');

  return RegExp(r'([A-Z][A-Z0-9_]*)\s*(?==|,|$)', multiLine: true)
      .allMatches(sansValeurs)
      .map((m) => m.group(1)!)
      .toSet();
}

/// Les clés d'une table Dart, **sans présumer de leur forme**.
///
/// ⚠️ Filtrer sur une convention de nommage ferait manquer les clés d'une autre
/// forme, signalerait un manque inexistant, et l'entrée ajoutée pour satisfaire
/// le contrôle créerait un doublon. On reconnaît donc toute chaîne littérale
/// suivie d'un `:`.
List<String> clesTable(String source) =>
    RegExp("""['"]([^'"]+)['"]\\s*:""")
        .allMatches(_sansCommentaires(source))
        .map((m) => m.group(1)!)
        .toList();

List<String> doublons(List<String> cles) {
  final vus = <String>{};
  final deuxFois = <String>[];
  for (final c in cles) {
    if (!vus.add(c)) deuxFois.add(c);
  }
  return deuxFois;
}

// ─────────────────────────────────────────────────────────────────────────────
// Racine du dépôt — pour que le contrôle marche depuis n'importe quel dossier
// ─────────────────────────────────────────────────────────────────────────────

Directory racineDepot() {
  var d = Directory.current.absolute;
  for (var i = 0; i < 8; i++) {
    if (Directory('${d.path}/apps/backend').existsSync() &&
        Directory('${d.path}/apps/mobile').existsSync()) {
      return d;
    }
    if (d.parent.path == d.path) break;
    d = d.parent;
  }
  stderr.writeln('❌ racine du dépôt introuvable depuis ${Directory.current.path}');
  stderr.writeln("   L'absence de verdict n'est pas un verdict.");
  exit(2);
}

// ─────────────────────────────────────────────────────────────────────────────
// Auto-test — autant de cas de refus que de cas qui passent
// ─────────────────────────────────────────────────────────────────────────────

int _ok = 0;
final _echecs = <String>[];

void _verifie(String libelle, Object obtenu, Object attendu) {
  if (obtenu.toString() == attendu.toString()) {
    _ok++;
  } else {
    _echecs.add('$libelle — attendu $attendu, obtenu $obtenu');
  }
}

bool selfTest() {
  // ── Doivent PASSER ────────────────────────────────────────────────────────
  _verifie('enum sur une ligne',
      membresEnum("export enum E { A = 'a', B = 'b' }", 'E').toList()..sort(), ['A', 'B']);
  _verifie('enum multi-lignes',
      membresEnum("enum E {\n  A = 'a',\n  LONG_NOM = 'x',\n}", 'E').toList()..sort(),
      ['A', 'LONG_NOM']);
  _verifie('clé pointée', clesTable("{'order.not_found': 'x'}"), ['order.not_found']);
  _verifie('clé courte sans séparateur', clesTable("{'not_found': 'x'}"), ['not_found']);
  _verifie('guillemets doubles', clesTable('{"A": "x"}'), ['A']);
  _verifie('doublon détecté', doublons(['a', 'b', 'a']), ['a']);
  _verifie('valeur interpolée reste une valeur',
      clesTable("{'A': 'limité à \$MAX unités'}"), ['A']);

  // ── Doivent REFUSER ───────────────────────────────────────────────────────
  _verifie('membre en commentaire ligne ignoré',
      membresEnum("enum E {\n  A = 'a',\n  // B = 'b',\n}", 'E').toList(), ['A']);
  _verifie('membre en bloc commentaire ignoré',
      membresEnum("enum E {\n  A = 'a',\n  /* B = 'b', */\n}", 'E').toList(), ['A']);
  _verifie('mauvais nom d’enum → rien', membresEnum("enum Autre { A = 'a' }", 'E').toList(), []);
  _verifie('clé en commentaire ignorée',
      clesTable("// {'fantome': 'x'}\n{'vrai': 'y'}"), ['vrai']);
  _verifie('URL dans une valeur n’est pas une clé', clesTable("{'a': 'http://x'}"), ['a']);
  _verifie('table vide → rien', clesTable('{}'), []);

  // ⚠️ Le cas qui garde ce fichier honnête : toute exclusion porte une raison
  // non vide. Sans lui, on pourrait neutraliser le contrôle en ajoutant une
  // clé sans justification.
  final sansRaison = _exclusions.entries.where((e) => e.value.trim().isEmpty).toList();
  _verifie('toute exclusion porte une raison', sansRaison.length, 0);

  const casRefus = 7;
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
── Éprouver ce vérificateur par MUTATION du vrai fichier ──

L'auto-test ne porte que sur des cas fabriqués : ils n'ont pas la structure des
vrais fichiers. Faire chaque mutation, vérifier que le contrôle REFUSE, puis
restaurer avec `git checkout -- <fichier>`.

  1. Ajouter un membre bidon à l'enum serveur        → 3 manques attendus
  2. Retirer une clé d'UNE seule table de langue     → 1 manque attendu
  3. Dupliquer une clé dans une table                → 1 doublon attendu
  4. Ajouter une clé inconnue du serveur             → 1 « en trop » attendu
  5. Renommer un fichier de table                    → ÉCHEC sur source
                                                       introuvable, jamais
                                                       « aucun écart »

Le cas 5 est le plus important : un contrôle qui conclut à l'accord quand il ne
trouve pas sa source est le mode de panne le plus dangereux de cette famille.
''');
}

// ─────────────────────────────────────────────────────────────────────────────

void main(List<String> args) {
  if (args.contains('--self-test')) exit(selfTest() ? 0 : 1);
  if (args.contains('--mutation')) return modeMutation();

  final racine = racineDepot();
  String lire(String relatif) {
    final f = File('${racine.path}/$relatif');
    if (!f.existsSync()) {
      stderr.writeln('❌ introuvable : $relatif');
      stderr.writeln("   L'absence de verdict n'est pas un verdict.");
      exit(2);
    }
    return f.readAsStringSync();
  }

  final serveur = membresEnum(lire(_sourceServeur), _nomEnum);
  if (serveur.isEmpty) {
    stderr.writeln('❌ enum $_nomEnum vide ou non reconnue dans $_sourceServeur');
    exit(2);
  }

  final attendus = serveur.difference(_exclusions.keys.toSet());
  stdout.writeln('serveur : ${serveur.length} codes '
      '− ${_exclusions.length} exclusion(s) épinglée(s) = ${attendus.length} à traduire\n');

  var problemes = 0;
  _tablesApp.forEach((langue, chemin) {
    final cles = clesTable(lire(chemin));
    final ensemble = cles.toSet();

    final manquants = attendus.difference(ensemble).toList()..sort();
    final enTrop = ensemble
        .difference(serveur)
        .difference(_codesClientSeuls.keys.toSet())
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
      stdout.writeln('       manque   $c  (servi, jamais traduit — l\'utilisateur '
          'verra le message backend, en français)');
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
    stdout.writeln('   Soit traduire le code, soit l\'épingler dans _exclusions '
        'AVEC sa raison — jamais le laisser sans décision.');
    exit(1);
  }
  stdout.writeln('✅ les ${_tablesApp.length} tables sont d\'accord avec le serveur.');
}
