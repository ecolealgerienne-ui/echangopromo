/// Vérifie que les **bornes de validation** recopiées côté application sont
/// encore celles du serveur (CLAUDE.md règle #7 : une valeur métier recopiée
/// nomme sa source, et un mécanisme la tient — pas un commentaire).
///
/// ── Pourquoi ce contrôle existe ──────────────────────────────────────────
///
/// Une borne recopiée est une règle qui vit ailleurs, recopiée **en silence**.
/// Le jour où le serveur passe de 8 à 12, l'écran continue d'accepter 8
/// caractères et affiche un refus que l'utilisateur ne comprend pas — personne
/// ne pense à chercher dans un écran la règle qu'on vient de changer dans un
/// DTO. Rien ne compile en rouge, et aucun test ne tombe.
///
/// ── Ce qui est comparé, et ce qui ne l'est pas ───────────────────────────
///
/// Ce contrôle lit les VRAIS fichiers des deux côtés : les décorateurs des DTO
/// NestJS d'une part, les nombres réellement écrits dans les écrans et widgets
/// d'autre part. Il ne s'appuie sur **aucune déclaration intermédiaire** — un
/// fichier de constantes que personne n'utiliserait donnerait une fausse
/// impression de couverture (« ce que le serveur sert doit avoir un appelant »).
///
/// ⚠️ Ne sont PAS couvertes les bornes serveur **sans copie côté app** — c'est
/// délibéré. L'absence ne ment pas, contrairement à une copie divergente : le
/// serveur refuse, l'app affiche le refus. Les épingler ici serait inventer une
/// dette.
///
/// ── Usage ────────────────────────────────────────────────────────────────
///
///   cd apps/mobile
///   dart run tool/check_server_rules.dart --self-test   # bloquant
///   dart run tool/check_server_rules.dart               # le contrôle
library;

import 'dart:io';

// ─────────────────────────────────────────────────────────────────────────────
// Les bornes recopiées
// ─────────────────────────────────────────────────────────────────────────────

class Borne {
  const Borne(this.libelle, this.dto, this.champ, this.decorateur,
      this.fichierApp, this.motifApp);

  final String libelle;
  final String dto;
  final String champ;
  final String decorateur;
  final String fichierApp;

  /// Doit capturer le nombre côté app dans son groupe 1.
  final String motifApp;
}

/// Une borne serveur qui ne vit pas dans un décorateur de DTO mais dans un
/// **défaut de configuration**
/// (`configNumber(this.configService.get('X'), 7, 'X')`).
///
/// ⚠️ Ajoutée le 2026-08-05 : le vérificateur ne savait lire que les
/// décorateurs, si bien que les durées de promo — recopiées en **trois**
/// exemplaires côté app — n'étaient tenues par rien. Ce qu'on ne sait pas lire
/// ne se signale pas tout seul comme non couvert : c'est le silence qui
/// ressemble le plus à un accord.
class BorneConfig {
  const BorneConfig(this.libelle, this.sourceTs, this.cleConfig,
      this.fichierApp, this.motifApp);

  final String libelle;
  final String sourceTs;

  /// La clé lue par `configService.get(...)`, ex. `PROMO_MAX_DURATION_DAYS`.
  final String cleConfig;
  final String fichierApp;
  final String motifApp;
}

const _bornesConfig = <BorneConfig>[
  BorneConfig(
      'durée de promo par défaut (jours)',
      'apps/backend/src/promo/promo.service.ts',
      'PROMO_DEFAULT_DURATION_DAYS',
      'apps/mobile/lib/domain/promo_rules.dart',
      r'promoDefaultDureeJours\s*=\s*(\d+)'),
  BorneConfig(
      'durée de promo maximale (jours)',
      'apps/backend/src/promo/promo.service.ts',
      'PROMO_MAX_DURATION_DAYS',
      'apps/mobile/lib/domain/promo_rules.dart',
      r'promoMaxDureeJours\s*=\s*(\d+)'),
];

/// Constantes serveur qui ne passent ni par un DTO ni par la configuration —
/// une simple `const` dans un service, recopiée côté app.
const _bornesConstantes = <BorneConfig>[
  // `cleConfig` sert ici de nom de constante TypeScript.
  BorneConfig(
      'fenêtre « expire bientôt » (heures)',
      'apps/backend/src/promo/promo.service.ts',
      'EXPIRING_SOON_WINDOW_HOURS',
      'apps/mobile/lib/domain/promo_rules.dart',
      r'promoExpiringSoonHours\s*=\s*(\d+)'),
];

/// La valeur d'une `const NOM = 42;` TypeScript.
int? constanteServeur(String source, String nom) {
  final m = RegExp('const\\s+$nom\\s*=\\s*(\\d+)')
      .firstMatch(_sansCommentaires(source));
  return m == null ? null : int.parse(m.group(1)!);
}

/// Le **défaut** d'un `configNumber(this.configService.get('CLE'), 7, 'CLE')`.
///
/// C'est bien le défaut qu'on compare, pas la valeur déployée : l'app ne peut
/// connaître que celui-là. Une variable d'environnement qui s'en écarte en
/// production reste hors de portée de ce contrôle — dit ici plutôt que laissé
/// croire couvert.
///
/// ⚠️ **La forme lue a changé le 2026-08-05** : elle était
/// `configService.get<number>('CLE', 7)`, dont l'annotation `<number>` ne
/// convertissait rien (une variable définie dans `.env` arrivait en chaîne).
/// Le motif est **ancré sur la forme d'appel complète** et non sur le seul nom
/// de clé, parce que celui-ci apparaît désormais deux fois dans le même appel
/// — s'ancrer sur lui rendrait la lecture ambiguë au lieu de la rendre
/// tolérante.
int? borneConfigServeur(String source, String cle) {
  final m = RegExp(
          "configNumber\\(\\s*this\\.configService\\.get\\(\\s*['\"]$cle['\"]\\s*\\)\\s*,\\s*(\\d+)")
      .firstMatch(_sansCommentaires(source));
  return m == null ? null : int.parse(m.group(1)!);
}

const _bornes = <Borne>[
  Borne(
      'description de promo (max)',
      'apps/backend/src/promo/dto/create-promo.dto.ts',
      'description',
      'MaxLength',
      'apps/mobile/lib/features/shared/widgets/promo_form_fields.dart',
      r'promoDescriptionMaxLength\s*=\s*(\d+)'),
  Borne(
      'titre de mise en avant (max)',
      'apps/backend/src/highlight/dto/create-highlight.dto.ts',
      'titre',
      'MaxLength',
      'apps/mobile/lib/features/admin/screens/admin_highlight_form_screen.dart',
      // ⚠️ Ancré sur le contrôleur du champ, pas sur `maxLength:` seul. Les
      // deux bornes de cet écran lisaient le même fichier avec le même motif
      // et comparaient à l'ENSEMBLE des nombres trouvés ({60, 100}) : chacune
      // « passait » sur la valeur de l'autre, et intervertir titre et
      // sous-titre restait vert (revue 2026-08-05, règle #28).
      r'_titreController[\s\S]{0,200}?maxLength:\s*(\d+)'),
  Borne(
      'sous-titre de mise en avant (max)',
      'apps/backend/src/highlight/dto/create-highlight.dto.ts',
      'sousTitre',
      'MaxLength',
      'apps/mobile/lib/features/admin/screens/admin_highlight_form_screen.dart',
      r'_sousTitreController[\s\S]{0,200}?maxLength:\s*(\d+)'),
  Borne(
      'mot de passe agent (min) — création',
      'apps/backend/src/agent/dto/create-agent.dto.ts',
      'password',
      'MinLength',
      'apps/mobile/lib/features/admin/screens/create_agent_screen.dart',
      r'length\s*<\s*(\d+)'),
  Borne(
      'mot de passe agent (min) — réinitialisation',
      'apps/backend/src/agent/dto/create-agent.dto.ts',
      'password',
      'MinLength',
      'apps/mobile/lib/features/admin/screens/agent_list_screen.dart',
      r'length\s*<\s*(\d+)'),
  Borne(
      'mot de passe (min) — connexion',
      'apps/backend/src/agent/dto/create-agent.dto.ts',
      'password',
      'MinLength',
      'apps/mobile/lib/features/commercant/screens/commercant_login_screen.dart',
      r'length\s*<\s*(\d+)'),
];

/// Les **motifs** (regex) recopiés, comparés sur leur texte.
class Motif {
  const Motif(
      this.libelle, this.sourceTs, this.nomTs, this.fichierApp, this.nomApp);
  final String libelle;
  final String sourceTs;
  final String nomTs;
  final String fichierApp;
  final String nomApp;
}

const _motifs = <Motif>[
  Motif(
      'PIN à fixer',
      'apps/backend/src/commercant/pin.constants.ts',
      'PIN_SET_PATTERN',
      'apps/mobile/lib/features/shared/validators/pin_validator.dart',
      '_pinSetPattern'),
  Motif(
      'PIN à vérifier',
      'apps/backend/src/commercant/pin.constants.ts',
      'PIN_VERIFY_PATTERN',
      'apps/mobile/lib/features/shared/validators/pin_validator.dart',
      '_pinVerifyPattern'),
];

// ─────────────────────────────────────────────────────────────────────────────
// Extraction
// ─────────────────────────────────────────────────────────────────────────────

String _sansCommentaires(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

/// La borne d'un décorateur posé sur un champ donné.
///
/// ⚠️ Le décorateur peut porter des options (`@MinLength(1, { each: true })`) :
/// on ne lit que le **premier** argument. Et il peut y avoir plusieurs
/// décorateurs entre lui et le champ — on regarde donc en avant jusqu'à la
/// première déclaration de champ, pas seulement la ligne suivante.
int? borneServeur(String source, String champ, String decorateur) {
  final lignes = _sansCommentaires(source).split('\n');
  final decl = RegExp('^\\s*(?:readonly\\s+)?$champ[?!]?\\s*:');

  for (var i = 0; i < lignes.length; i++) {
    final m = RegExp('@$decorateur\\(\\s*(\\d+)').firstMatch(lignes[i]);
    if (m == null) continue;
    for (var j = i + 1; j < lignes.length && j <= i + 10; j++) {
      if (decl.hasMatch(lignes[j])) return int.parse(m.group(1)!);
      // Un autre décorateur de champ intercalé : on continue.
      if (lignes[j].trim().isEmpty || lignes[j].trimLeft().startsWith('@')) {
        continue;
      }
      break; // autre chose → ce décorateur ne porte pas sur `champ`
    }
  }
  return null;
}

/// Tous les nombres capturés par [motif] dans une source d'application.
Set<int> nombresApp(String source, String motif) => RegExp(motif)
    .allMatches(_sansCommentaires(source))
    .map((m) => int.parse(m.group(1)!))
    .toSet();

/// Le texte d'un motif régulier, quel que soit le langage.
///
/// TS : `export const X = /^\d{6,12}$/;`  →  `^\d{6,12}$`
/// Dart : `final X = RegExp(r'^\d{6,12}$');` → `^\d{6,12}$`
String? motifRegex(String source, String nom) {
  final propre = _sansCommentaires(source);
  final ts = RegExp('$nom\\s*=\\s*/(.+?)/[gimsuy]*\\s*;').firstMatch(propre);
  if (ts != null) return ts.group(1);
  final dart =
      RegExp("$nom\\s*=\\s*RegExp\\(\\s*r?['\"](.+?)['\"]").firstMatch(propre);
  return dart?.group(1);
}

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
  stderr.writeln(
      '❌ racine du dépôt introuvable depuis ${Directory.current.path}');
  stderr.writeln("   L'absence de verdict n'est pas un verdict.");
  exit(2);
}

// ─────────────────────────────────────────────────────────────────────────────
// Auto-test
// ─────────────────────────────────────────────────────────────────────────────

int _ok = 0;
final _echecs = <String>[];

void _verifie(String libelle, Object? obtenu, Object? attendu) {
  if (obtenu.toString() == attendu.toString()) {
    _ok++;
  } else {
    _echecs.add('$libelle — attendu $attendu, obtenu $obtenu');
  }
}

bool selfTest() {
  const dto = '''
export class D {
  @IsString()
  @MinLength(2)
  @MaxLength(140)
  description: string;

  @IsOptional()
  @MaxLength(60)
  titre?: string;

  @MinLength(1, { each: true })
  photoKeys: string[];
}
''';

  // ── Doivent PASSER ────────────────────────────────────────────────────────
  _verifie('MaxLength à travers un autre décorateur',
      borneServeur(dto, 'description', 'MaxLength'), 140);
  _verifie('MinLength du même champ',
      borneServeur(dto, 'description', 'MinLength'), 2);
  _verifie(
      'champ optionnel (titre?)', borneServeur(dto, 'titre', 'MaxLength'), 60);
  _verifie('décorateur avec options',
      borneServeur(dto, 'photoKeys', 'MinLength'), 1);
  _verifie(
      'nombres côté app',
      nombresApp('maxLength: 60,\nmaxLength: 100,', r'maxLength:\s*(\d+)')
          .toList()
        ..sort(),
      [60, 100]);
  _verifie('motif TS', motifRegex(r"export const P = /^\d{6,12}$/;", 'P'),
      r'^\d{6,12}$');
  _verifie('motif Dart', motifRegex(r"final P = RegExp(r'^\d{6,12}$');", 'P'),
      r'^\d{6,12}$');

  // ── Doivent REFUSER ───────────────────────────────────────────────────────
  // ⚠️ Le cas fondateur : un décorateur qui ne porte PAS sur le champ cherché
  // ne doit pas être attribué. Sans la borne « autre chose → on arrête », le
  // @MaxLength(140) de `description` serait lu comme celui de `titre`.
  _verifie(
      'décorateur d’un AUTRE champ non attribué',
      borneServeur('@MaxLength(9)\n  autre: string;\n\n  titre: string;',
          'titre', 'MaxLength'),
      null);
  _verifie('champ absent → null', borneServeur(dto, 'inexistant', 'MaxLength'),
      null);
  _verifie('décorateur absent → null', borneServeur(dto, 'description', 'Min'),
      null);
  _verifie(
      'décorateur en commentaire ignoré',
      borneServeur('// @MaxLength(140)\n  description: string;', 'description',
          'MaxLength'),
      null);
  _verifie('aucun nombre côté app → ensemble vide',
      nombresApp('rien ici', r'maxLength:\s*(\d+)').toList(), []);
  _verifie(
      'motif introuvable → null', motifRegex('const autre = 1;', 'P'), null);
  _verifie(
      'défaut de configuration lu',
      borneConfigServeur(
          "return configNumber(this.configService.get('PROMO_MAX_DURATION_DAYS'), 7, 'PROMO_MAX_DURATION_DAYS');",
          'PROMO_MAX_DURATION_DAYS'),
      7);
  // La forme réellement écrite dans le service après passage de Prettier :
  // repliée sur quatre lignes. Un motif qui ne tolérerait pas les sauts de
  // ligne passerait l'auto-test et échouerait sur le vrai fichier.
  _verifie('défaut de configuration replié sur plusieurs lignes',
      borneConfigServeur('''
    return configNumber(
      this.configService.get('PROMO_DEFAULT_DURATION_DAYS'),
      5,
      'PROMO_DEFAULT_DURATION_DAYS',
    );
''', 'PROMO_DEFAULT_DURATION_DAYS'), 5);
  _verifie(
      'clé de configuration absente → null',
      borneConfigServeur("configNumber(this.configService.get('AUTRE'), 7);",
          'PROMO_MAX_DURATION_DAYS'),
      null);
  _verifie(
      'défaut de configuration en commentaire ignoré',
      borneConfigServeur(
          "// configNumber(this.configService.get('PROMO_MAX_DURATION_DAYS'), 7);",
          'PROMO_MAX_DURATION_DAYS'),
      null);
  // ⚠️ L'ancienne forme ne doit PLUS être reconnue : elle rendait une chaîne
  // là où un nombre était annoncé. La laisser passer ferait juger conforme un
  // service qu'on vient justement de corriger.
  _verifie(
      'ancienne forme get<number> refusée',
      borneConfigServeur(
          "this.configService.get<number>('PROMO_MAX_DURATION_DAYS', 7);",
          'PROMO_MAX_DURATION_DAYS'),
      null);
  // Le nom de clé apparaît deux fois dans l'appel : la seconde occurrence (le
  // libellé de journalisation) ne doit pas être lue comme une borne.
  _verifie(
      'libellé de journalisation non confondu avec la borne',
      borneConfigServeur(
          "configNumber(this.configService.get('CLE'), 42, 'CLE'), 99", 'CLE'),
      42);
  _verifie(
      'constante serveur lue',
      constanteServeur('const EXPIRING_SOON_WINDOW_HOURS = 24;',
          'EXPIRING_SOON_WINDOW_HOURS'),
      24);
  _verifie(
      'constante absente → null',
      constanteServeur('const AUTRE = 24;', 'EXPIRING_SOON_WINDOW_HOURS'),
      null);
  _verifie(
      'constante en commentaire ignorée',
      constanteServeur('// const EXPIRING_SOON_WINDOW_HOURS = 24;',
          'EXPIRING_SOON_WINDOW_HOURS'),
      null);

  const casRefus = 11;
  final total = _ok + _echecs.length;
  stdout.writeln('auto-test : $total cas, dont $casRefus refus');
  for (final e in _echecs) {
    stdout.writeln('  ❌ $e');
  }
  stdout.writeln('  $_ok/$total');
  return _echecs.isEmpty;
}

// ─────────────────────────────────────────────────────────────────────────────

void main(List<String> args) {
  if (args.contains('--self-test')) exit(selfTest() ? 0 : 1);

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

  stdout.writeln('── bornes numériques ──');
  for (final b in _bornes) {
    final serveur = borneServeur(lire(b.dto), b.champ, b.decorateur);
    if (serveur == null) {
      stdout.writeln('  ❌ ${b.libelle}');
      stdout.writeln(
          '       @${b.decorateur} sur `${b.champ}` introuvable dans ${b.dto}');
      stdout.writeln(
          '       Le DTO a-t-il changé ? Un contrôle qui ne trouve plus sa '
          'cible ne conclut pas.');
      problemes++;
      continue;
    }

    final app = nombresApp(lire(b.fichierApp), b.motifApp);
    if (app.isEmpty) {
      stdout.writeln('  ❌ ${b.libelle}');
      stdout.writeln('       aucune valeur trouvée dans ${b.fichierApp}');
      stdout.writeln(
          '       (motif : ${b.motifApp}) — l\'ancre a-t-elle bougé ?');
      problemes++;
      continue;
    }
    // ⚠️ Un motif qui rend PLUSIEURS valeurs ne désigne pas une borne : il
    // désigne une zone. `app.contains(serveur)` y devient un test « la bonne
    // valeur est quelque part dans le fichier », que deux bornes voisines
    // satisfont mutuellement — c'est exactement ce qui laissait passer
    // l'interversion titre/sous-titre. Un motif ambigu est refusé, pas toléré.
    if (app.length > 1) {
      stdout.writeln('  ❌ ${b.libelle}');
      stdout.writeln(
          '       motif ambigu : ${app.length} valeurs trouvées ${app.toList()..sort()}');
      stdout.writeln(
          '       (motif : ${b.motifApp}) — l\'ancrer sur le champ, pas sur le fichier.');
      problemes++;
      continue;
    }
    if (!app.contains(serveur)) {
      stdout.writeln('  ❌ ${b.libelle}');
      stdout.writeln('       serveur $serveur, app ${app.toList()..sort()}');
      problemes++;
      continue;
    }
    stdout.writeln('  ✅ ${b.libelle.padRight(42)} $serveur');
  }

  stdout.writeln('\n── bornes de configuration et constantes ──');
  for (final b in [..._bornesConfig, ..._bornesConstantes]) {
    final estConstante = _bornesConstantes.contains(b);
    final source = lire(b.sourceTs);
    final serveur = estConstante
        ? constanteServeur(source, b.cleConfig)
        : borneConfigServeur(source, b.cleConfig);
    if (serveur == null) {
      stdout.writeln('  ❌ ${b.libelle}');
      stdout.writeln(estConstante
          ? '       `const ${b.cleConfig} = …` introuvable dans ${b.sourceTs}'
          : '       `get<number>(\'${b.cleConfig}\', …)` introuvable dans ${b.sourceTs}');
      problemes++;
      continue;
    }
    final app = nombresApp(lire(b.fichierApp), b.motifApp);
    if (app.length != 1) {
      stdout.writeln('  ❌ ${b.libelle}');
      stdout.writeln(app.isEmpty
          ? '       aucune valeur trouvée (motif : ${b.motifApp})'
          : '       motif ambigu : ${app.toList()..sort()}');
      problemes++;
      continue;
    }
    if (!app.contains(serveur)) {
      stdout.writeln('  ❌ ${b.libelle}');
      stdout.writeln('       serveur $serveur, app ${app.toList()}');
      problemes++;
      continue;
    }
    stdout.writeln('  ✅ ${b.libelle.padRight(42)} $serveur');
  }

  stdout.writeln('\n── motifs réguliers ──');
  for (final m in _motifs) {
    final ts = motifRegex(lire(m.sourceTs), m.nomTs);
    final dart = motifRegex(lire(m.fichierApp), m.nomApp);
    if (ts == null || dart == null) {
      stdout.writeln('  ❌ ${m.libelle} — motif introuvable '
          '(${ts == null ? m.nomTs : m.nomApp})');
      problemes++;
      continue;
    }
    if (ts != dart) {
      stdout.writeln('  ❌ ${m.libelle}');
      stdout.writeln('       serveur  $ts');
      stdout.writeln('       app      $dart');
      problemes++;
      continue;
    }
    stdout.writeln('  ✅ ${m.libelle.padRight(42)} $ts');
  }

  stdout.writeln();
  if (problemes > 0) {
    stdout.writeln('❌ $problemes borne(s) divergente(s) ou introuvable(s).');
    exit(1);
  }
  stdout.writeln(
      '✅ ${_bornes.length + _bornesConfig.length + _bornesConstantes.length} '
      'bornes et ${_motifs.length} motifs sont d\'accord avec le serveur.');
}
