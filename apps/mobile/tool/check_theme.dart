/// Vérifie qu'une couleur **sémantique** vient du thème, et recense les
/// espacements littéraux (CLAUDE.md règle 35).
///
/// ── Pourquoi ce contrôle existe ──────────────────────────────────────────
///
/// L'application a un basculement clair/sombre depuis fin juillet 2026. Une
/// couleur écrite en dur **ne suit pas le basculement** : l'écran est
/// simplement faux dans un des deux thèmes, sans erreur, sans journal, et
/// personne ne regarde les deux côte à côte.
///
/// ── Ce qu'il refuse, et ce qu'il admet ───────────────────────────────────
///
/// ⚠️ **Un interdit général sur `Colors.*` serait une règle fausse ici**, et
/// la mesure du 2026-08-04 le montre : sur 12 occurrences, la plupart sont des
/// blancs et des noirs posés **au-dessus d'une photo ou d'une tuile de carte**.
/// Le contraste s'y joue contre un contenu arbitraire, pas contre une surface
/// de thème — les faire passer par `colorScheme` les rendrait illisibles sur
/// une image claire.
///
/// On refuse donc les couleurs **sémantiques** (succès, alerte, accent,
/// favori…), qui ont toutes un équivalent dans `colorScheme` ou dans
/// l'extension `AppSemanticColors`. On admet `white`/`black`/`transparent` et
/// les valeurs hexadécimales **dans les fichiers épinglés ci-dessous**, chacun
/// avec sa raison.
///
/// ── Ce qu'il ne fait PAS ─────────────────────────────────────────────────
///
/// Il **recense** les espacements littéraux sans échouer. Il n'existe pas
/// encore de barème (`AppSpacing`) : refuser sans barème demanderait de
/// converger vers rien, et faire converger 200 valeurs déplace des pixels —
/// c'est une décision de design, pas un défaut.
///
/// ── Usage ────────────────────────────────────────────────────────────────
///
///   cd apps/mobile
///   dart run tool/check_theme.dart --self-test
///   dart run tool/check_theme.dart
library;

import 'dart:io';

// ─────────────────────────────────────────────────────────────────────────────

const _racineFeatures = 'apps/mobile/lib/features';

/// Dossiers hors cible, avec leur raison.
const _horsCible = <String, String>{
  'dev': 'outil de développement, pas une surface produit',
};

/// Couleurs nommées de Flutter qui ont un équivalent dans le thème — donc
/// refusées. La liste est **explicite** : une couleur inconnue d'ici passe,
/// parce qu'un refus par défaut sur un nom qu'on n'a pas examiné accuserait à
/// l'aveugle.
const _semantiquesInterdites = <String>{
  'red',
  'redAccent',
  'green',
  'greenAccent',
  'blue',
  'blueAccent',
  'amber',
  'amberAccent',
  'orange',
  'orangeAccent',
  'yellow',
  'grey',
  'blueGrey',
  'purple',
  'teal',
  'pink',
  'indigo',
  'cyan',
  'lime',
};

/// Neutres admis — mais seulement dans les fichiers épinglés ci-dessous.
const _neutres = <String>{
  'white',
  'black',
  'transparent',
  'white70',
  'black54'
};

/// Fichiers autorisés à poser un neutre ou une valeur hexadécimale, AVEC leur
/// raison.
///
/// ⚠️ Ne jamais y ajouter une entrée pour faire passer le contrôle : une
/// exception sans raison est indiscernable d'un oubli, et l'auto-test la
/// refuse.
const _epingles = <String, String>{
  'client/screens/map_screen.dart':
      'marqueur de position au-dessus des tuiles de carte — contraste contre la carte, pas contre le thème',
  'client/screens/promo_list_screen.dart':
      'superpositions au-dessus des photos de promo',
  'client/widgets/promo_grid_card.dart':
      'libellé au-dessus de la photo de promo',
  'shared/widgets/promo_photo_hero.dart':
      'indicateurs au-dessus de la photo plein écran',
  'shared/widgets/multi_photo_picker_field.dart':
      'voile noir et croix blanche au-dessus de la vignette photo',
};

final _couleurNommee = RegExp(r'(?:^|[^a-zA-Z.])Colors\.([a-zA-Z0-9]+)');
final _couleurHexa = RegExp(r'Color\(0x[0-9A-Fa-f]+\)');
final _espacement =
    RegExp(r'EdgeInsets\.(?:all|symmetric|only|fromLTRB)\(\s*[a-z:\s]*\d|'
        r'SizedBox\(\s*(?:height|width):\s*\d|'
        r'BorderRadius\.circular\(\s*\d');

String _sansCommentaires(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

// ─────────────────────────────────────────────────────────────────────────────
// Le verdict d'une occurrence — la logique que l'auto-test éprouve
// ─────────────────────────────────────────────────────────────────────────────

/// Rend `null` si l'occurrence est admise, sinon le motif du refus.
String? verdictCouleur(String nom, String cheminRelatif) {
  if (_semantiquesInterdites.contains(nom)) {
    return 'couleur sémantique en dur — passer par colorScheme ou AppSemanticColors';
  }
  if (_neutres.contains(nom)) {
    return _epingles.containsKey(cheminRelatif)
        ? null
        : 'neutre en dur dans un fichier non épinglé — l\'épingler avec sa raison, '
            'ou passer par le thème';
  }
  return null; // nom non examiné : on n'accuse pas à l'aveugle
}

String? verdictHexa(String cheminRelatif) => _epingles
        .containsKey(cheminRelatif)
    ? null
    : 'valeur hexadécimale en dur — la nommer dans le thème, ou épingler le fichier';

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
  final egal = (obtenu == null && attendu == null) ||
      (obtenu != null &&
          attendu != null &&
          obtenu.toString().contains(attendu.toString()));
  if (egal) {
    _ok++;
  } else {
    _echecs.add(
        '$libelle — obtenu ${obtenu ?? "admis"}, attendu ${attendu ?? "admis"}');
  }
}

bool selfTest() {
  const epingle = 'client/screens/map_screen.dart';
  const libre = 'admin/screens/admin_dashboard_screen.dart';

  // ── Doivent PASSER (admis) ────────────────────────────────────────────────
  _verifie(
      'neutre dans un fichier épinglé', verdictCouleur('white', epingle), null);
  _verifie('transparent dans un fichier épinglé',
      verdictCouleur('transparent', epingle), null);
  _verifie('hexa dans un fichier épinglé', verdictHexa(epingle), null);
  _verifie('nom non examiné → admis',
      verdictCouleur('deepPurpleAccent700', libre), null);
  _verifie('extraction ignore les commentaires',
      _couleurNommee.hasMatch(_sansCommentaires('// Colors.red')), false);
  _verifie('semanticColors.success n\'est PAS Colors.success',
      _couleurNommee.hasMatch('semanticColors.success'), false);

  // ── Doivent REFUSER ───────────────────────────────────────────────────────
  _verifie('sémantique interdite partout', verdictCouleur('redAccent', epingle),
      'sémantique');
  _verifie('sémantique dans un fichier libre', verdictCouleur('amber', libre),
      'sémantique');
  _verifie(
      'neutre hors épinglage', verdictCouleur('white', libre), 'non épinglé');
  _verifie('hexa hors épinglage', verdictHexa(libre), 'hexadécimale');
  _verifie('Colors.red bien détecté',
      _couleurNommee.firstMatch(' Colors.red')?.group(1), 'red');
  _verifie('espacement littéral détecté',
      _espacement.hasMatch('EdgeInsets.all(16)'), true);

  // Garde-fou : toute exception porte une raison non vide.
  _verifie('tout épinglage porte une raison',
      _epingles.values.where((v) => v.trim().isEmpty).length, 0);

  const casRefus = 7;
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
  final dir = Directory('${racine.path}/$_racineFeatures');
  if (!dir.existsSync()) {
    stderr.writeln('❌ introuvable : $_racineFeatures');
    stderr.writeln("   L'absence de verdict n'est pas un verdict.");
    exit(2);
  }

  final refus = <String>[];
  final espacementsParDossier = <String, int>{};
  var fichiers = 0;

  for (final f in dir.listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    final relatif = f.path
        .substring(f.path.indexOf('features${Platform.pathSeparator}') + 9)
        .replaceAll(Platform.pathSeparator, '/');
    final dossier = relatif.split('/').first;
    if (_horsCible.containsKey(dossier)) continue;
    fichiers++;

    final source = _sansCommentaires(f.readAsStringSync());

    for (final m in _couleurNommee.allMatches(source)) {
      final motif = verdictCouleur(m.group(1)!, relatif);
      if (motif != null) {
        final ligne = '\n'.allMatches(source.substring(0, m.start)).length + 1;
        refus.add('$relatif:$ligne  Colors.${m.group(1)} — $motif');
      }
    }
    for (final m in _couleurHexa.allMatches(source)) {
      final motif = verdictHexa(relatif);
      if (motif != null) {
        final ligne = '\n'.allMatches(source.substring(0, m.start)).length + 1;
        refus.add('$relatif:$ligne  ${m.group(0)} — $motif');
      }
    }
    final n = _espacement.allMatches(source).length;
    if (n > 0) {
      espacementsParDossier[dossier] =
          (espacementsParDossier[dossier] ?? 0) + n;
    }
  }

  stdout.writeln('── couleurs ──');
  stdout.writeln('$fichiers fichiers examinés, '
      '${_epingles.length} fichier(s) épinglé(s), '
      '${_horsCible.length} dossier(s) hors cible\n');
  for (final r in refus) {
    stdout.writeln('  ❌ $r');
  }
  if (refus.isEmpty) stdout.writeln('  ✅ aucune couleur sémantique en dur');

  stdout.writeln('\n── espacements littéraux (recensés, non bloquants) ──');
  final total = espacementsParDossier.values.fold<int>(0, (a, b) => a + b);
  final tries = espacementsParDossier.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in tries) {
    stdout.writeln('  ${e.value.toString().padLeft(4)}  ${e.key}');
  }
  stdout.writeln('  ${total.toString().padLeft(4)}  total');
  stdout.writeln(
      '  ⓘ pas de barème `AppSpacing` à ce jour : refuser demanderait de');
  stdout.writeln(
      '    converger vers rien, et faire converger déplace des pixels.');

  stdout.writeln();
  if (refus.isNotEmpty) {
    stdout.writeln('❌ ${refus.length} couleur(s) à traiter.');
    exit(1);
  }
  stdout.writeln('✅ les couleurs sémantiques passent toutes par le thème.');
}
