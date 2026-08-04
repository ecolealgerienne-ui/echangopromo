/// Vérifie que chaque enum Dart miroir porte exactement les mêmes **valeurs
/// réseau** que l'enum backend dont il est le miroir (CLAUDE.md règle #19).
///
/// ── Pourquoi ce contrôle existe ──────────────────────────────────────────
///
/// La règle 19 impose un enum Dart miroir plutôt qu'une `String` brute, pour
/// que le compilateur attrape un renommage. Elle ne protège pas du cas
/// inverse : le backend **ajoute** ou **renomme** une valeur, et le miroir ne
/// bouge pas. Rien ne compile en rouge — la valeur inconnue est simplement mal
/// interprétée, souvent en silence (voir l'avertissement sur les replis).
///
/// La comparaison porte sur la **valeur réseau** (`'vetements_textile'`), pas
/// sur le nom du membre : c'est elle qui voyage dans le JSON, et les deux
/// langages ont des conventions de nommage différentes.
///
/// ── Usage ────────────────────────────────────────────────────────────────
///
///   cd apps/mobile
///   dart run tool/check_enums.dart --self-test   # bloquant
///   dart run tool/check_enums.dart               # le contrôle
///   dart run tool/check_enums.dart --mutation    # comment l'éprouver
library;

import 'dart:io';

// ─────────────────────────────────────────────────────────────────────────────
// Les couples à tenir d'accord
// ─────────────────────────────────────────────────────────────────────────────

class Paire {
  const Paire(this.libelle, this.sourceTs, this.enumTs, this.sourceDart, this.enumDart);
  final String libelle;
  final String sourceTs;
  final String enumTs;
  final String sourceDart;
  final String enumDart;
}

const _paires = <Paire>[
  Paire('Catégorie',
      'apps/backend/src/common/enums/categorie.enum.ts', 'Categorie',
      'apps/mobile/lib/domain/enums/categorie.dart', 'Categorie'),
  Paire('Cycle de vie promo',
      'apps/backend/src/promo/entities/promo.entity.ts', 'PromoLifecycleStatus',
      'apps/mobile/lib/domain/enums/promo_lifecycle_status.dart', 'PromoLifecycleStatus'),
  Paire('Modération promo',
      'apps/backend/src/promo/entities/promo.entity.ts', 'PromoModerationStatus',
      'apps/mobile/lib/domain/enums/promo_moderation_status.dart', 'PromoModerationStatus'),
  Paire('État de compte commerçant',
      'apps/backend/src/commercant/entities/commercant.entity.ts', 'CommercantAccountState',
      'apps/mobile/lib/domain/enums/commercant_account_state.dart', 'CommercantAccountState'),
  Paire('Vérification d\'origine',
      'apps/backend/src/commercant/entities/commercant.entity.ts', 'CommercantOriginVerification',
      'apps/mobile/lib/domain/enums/commercant_origin_verification.dart',
      'CommercantOriginVerification'),
  Paire('Statut du registre',
      'apps/backend/src/commercant/entities/commercant.entity.ts', 'RegistreStatus',
      'apps/mobile/lib/domain/enums/registre_status.dart', 'RegistreStatus'),
  Paire('Motif de signalement',
      'apps/backend/src/report/entities/report.entity.ts', 'ReportReason',
      'apps/mobile/lib/domain/enums/report_reason.dart', 'ReportReason'),
  Paire('Type d\'acteur (audit)',
      'apps/backend/src/audit-log/entities/audit-log.entity.ts', 'AuditActorType',
      'apps/mobile/lib/domain/enums/audit_actor_type.dart', 'AuditActorType'),
];

/// Enums Dart **sans** contrepartie backend, épinglés avec leur raison.
///
/// ⚠️ Comme pour les exclusions de `check_error_codes.dart` : une entrée sans
/// raison est indiscernable d'un oubli, et l'auto-test la refuse.
const _mobileSeuls = <String, String>{
  'onboarding_role.dart':
      'choix de rôle au premier lancement — purement local, jamais envoyé au serveur',
};

// ─────────────────────────────────────────────────────────────────────────────
// Extraction
// ─────────────────────────────────────────────────────────────────────────────

String _sansCommentaires(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

/// Les **valeurs** d'un enum TypeScript (`ALIMENTATION = 'alimentation'`).
///
/// ⚠️ On lit la valeur, jamais le nom du membre : c'est elle qui voyage dans le
/// JSON. Les deux langages nomment différemment (`VETEMENTS_TEXTILE` côté TS,
/// `vetementsTextile` côté Dart) — comparer les noms ne dirait rien.
Set<String> valeursTs(String source, String nom) {
  final bloc =
      RegExp('enum\\s+$nom\\s*\\{([^}]*)\\}').firstMatch(_sansCommentaires(source));
  if (bloc == null) return <String>{};
  return RegExp("""=\\s*['"]([^'"]*)['"]""")
      .allMatches(bloc.group(1)!)
      .map((m) => m.group(1)!)
      .toSet();
}

/// Les **valeurs** d'un enum Dart amélioré (`vetementsTextile('vetements_textile')`).
///
/// ⚠️ Le corps s'arrête au premier `;` — au-delà vivent le constructeur, les
/// champs et les méthodes, dont les chaînes ne sont **pas** des valeurs
/// d'énumération. Sans cette borne, `fromValue` et ses messages seraient lus
/// comme des membres.
Set<String> valeursDart(String source, String nom) {
  final propre = _sansCommentaires(source);
  final debut = RegExp('enum\\s+$nom\\s*\\{').firstMatch(propre);
  if (debut == null) return <String>{};

  final reste = propre.substring(debut.end);
  final finPointVirgule = reste.indexOf(';');
  final finAccolade = reste.indexOf('}');
  var fin = finPointVirgule;
  if (fin < 0 || (finAccolade >= 0 && finAccolade < fin)) fin = finAccolade;
  if (fin < 0) fin = reste.length;

  return RegExp("""\\(\\s*['"]([^'"]*)['"]\\s*\\)""")
      .allMatches(reste.substring(0, fin))
      .map((m) => m.group(1)!)
      .toSet();
}

/// Les miroirs Dart dont `fromValue` **avale** une valeur inconnue.
///
/// Ce n'est pas un échec — c'est parfois un choix. Mais c'est le mode de
/// défaillance « un défaut n'a pas de valeur par défaut » : une valeur ajoutée
/// côté serveur devient silencieusement autre chose, sans erreur ni journal.
bool repliSilencieux(String source) =>
    RegExp(r'orElse\s*:').hasMatch(_sansCommentaires(source));

// ─────────────────────────────────────────────────────────────────────────────
// Racine du dépôt
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
// Auto-test
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
  _verifie('TS simple',
      (valeursTs("export enum E { A = 'a', B = 'b' }", 'E').toList()..sort()), ['a', 'b']);
  _verifie('TS multi-lignes',
      (valeursTs("enum E {\n  A = 'a',\n  LONG = 'long_x',\n}", 'E').toList()..sort()),
      ['a', 'long_x']);
  _verifie('Dart amélioré',
      (valeursDart("enum E {\n  a('a'),\n  bC('b_c');\n\n  const E(this.value);\n}", 'E')
          .toList()
        ..sort()),
      ['a', 'b_c']);
  _verifie('repli silencieux détecté',
      repliSilencieux("firstWhere((s) => s.value == v, orElse: () => E.a)"), true);

  // ── Doivent REFUSER ───────────────────────────────────────────────────────
  // ⚠️ Le cas fondateur : les chaînes situées APRÈS le `;` ne sont pas des
  // valeurs. Sans la borne, `fromValue` et son message seraient comptés.
  _verifie('Dart : rien après le point-virgule',
      (valeursDart(
              "enum E {\n  a('a');\n\n  const E(this.value);\n  final String value;\n"
              "  static E f(String v) => E.values.firstWhere((x) => x.value == v);\n"
              "  String get libelle => tr('e.libelle');\n}",
              'E')
          .toList()),
      ['a']);
  _verifie('TS : membre en commentaire ignoré',
      (valeursTs("enum E {\n  A = 'a',\n  // B = 'b',\n}", 'E').toList()), ['a']);
  _verifie('Dart : membre en commentaire ignoré',
      (valeursDart("enum E {\n  a('a'),\n  // b('b'),\n  c('c');\n}", 'E').toList()..sort()),
      ['a', 'c']);
  _verifie('mauvais nom d’enum → rien', valeursTs("enum Autre { A = 'a' }", 'E').toList(), []);
  _verifie('enum absent → rien', valeursDart("class X {}", 'E').toList(), []);
  _verifie('absence de repli reconnue',
      repliSilencieux("E.values.firstWhere((x) => x.value == v)"), false);

  // Garde-fou identique à check_error_codes : toute exception porte sa raison.
  _verifie('tout enum mobile-seul porte une raison',
      _mobileSeuls.values.where((v) => v.trim().isEmpty).length, 0);

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
── Éprouver ce vérificateur par MUTATION des vrais fichiers ──

⚠️ Committer AVANT de muter : un lanceur qui restaure par
`git checkout -- .` balaie aussi le travail non commité.

  1. Ajouter une valeur à un enum backend      → 1 « manque côté app »
  2. Retirer une valeur d'un miroir Dart       → 1 « manque côté app »
  3. Changer une valeur d'un côté seulement    → 1 manque + 1 « en trop »
  4. Renommer un fichier de miroir             → ÉCHEC sur source introuvable,
                                                  jamais « tout est d'accord »
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

  var problemes = 0;
  final replis = <String>[];

  for (final p in _paires) {
    final ts = valeursTs(lire(p.sourceTs), p.enumTs);
    final sourceDart = lire(p.sourceDart);
    final dart = valeursDart(sourceDart, p.enumDart);

    if (ts.isEmpty) {
      stdout.writeln('  ❌ ${p.libelle} — enum ${p.enumTs} introuvable dans ${p.sourceTs}');
      problemes++;
      continue;
    }
    if (dart.isEmpty) {
      stdout.writeln('  ❌ ${p.libelle} — enum ${p.enumDart} introuvable dans ${p.sourceDart}');
      problemes++;
      continue;
    }

    final manquants = ts.difference(dart).toList()..sort();
    final enTrop = dart.difference(ts).toList()..sort();
    if (repliSilencieux(sourceDart)) replis.add(p.libelle);

    if (manquants.isEmpty && enTrop.isEmpty) {
      stdout.writeln('  ✅ ${p.libelle.padRight(28)} ${ts.length} valeurs');
      continue;
    }
    problemes++;
    stdout.writeln('  ❌ ${p.libelle}');
    for (final v in manquants) {
      stdout.writeln("       serveur seul   '$v'  (émis par l'API, inconnu du miroir)");
    }
    for (final v in enTrop) {
      stdout.writeln("       app seule      '$v'  (attendu par l'app, jamais émis)");
    }
  }

  stdout.writeln();
  if (replis.isNotEmpty) {
    stdout.writeln('⚠️  ${replis.length} miroir(s) avec un repli silencieux '
        '(`orElse`) : ${replis.join(', ')}.');
    stdout.writeln('    Une valeur ajoutée côté serveur y devient autre chose sans');
    stdout.writeln('    erreur ni journal. Non bloquant — mais à décider, pas à subir.');
    stdout.writeln();
  }
  if (problemes > 0) {
    stdout.writeln('❌ $problemes couple(s) désynchronisé(s).');
    exit(1);
  }
  stdout.writeln('✅ les ${_paires.length} couples sont d\'accord '
      '(${_mobileSeuls.length} enum mobile-seul épinglé).');
}
