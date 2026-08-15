// Génère `lib/features/shared/data/pays.dart` — la liste des 245 pays servie
// au sélecteur d'indicatif téléphonique.
//
// Lancer depuis `apps/mobile` :  node tool/generer_pays.mjs
// puis :                        dart format lib/features/shared/data/pays.dart
//
// ── Pourquoi générer plutôt que prendre un package ────────────────────────
//
// Un package de sélecteur de pays apporterait la liste ET son widget, donc son
// style, ses traductions partielles et son rythme de mises à jour — le même
// raisonnement qui a fait écrire le regroupement de marqueurs à la main plutôt
// que de prendre un paquet de clustering (voir `pubspec.yaml`). Ici, tout ce
// dont on a besoin est déjà sur la machine :
//
//   - `libphonenumber-js` (dépendance du backend) donne les codes ISO, les
//     indicatifs et un numéro d'exemple par pays ;
//   - `Intl.DisplayNames` de Node donne les noms localisés — les mêmes données
//     CLDR que celles qu'embarquerait un package.
//
// ⚠️ **Les noms de pays ne passent PAS par les fichiers `.arb`** (règle 27), et
// c'est délibéré : 245 pays × 3 langues, ce sont 735 chaînes qui ne sont pas de
// l'interface mais de la **donnée de référence**. Les mettre dans les `.arb`
// noierait les ~200 vraies chaînes d'interface et rendrait toute relecture de
// traduction impraticable. Ce qui reste dans les `.arb`, c'est le libellé du
// champ et le texte de recherche — l'interface, justement.
//
// ⚠️ Le fichier produit est **committé**. Le régénérer ne doit rien changer
// tant que Node et libphonenumber-js n'ont pas bougé : c'est ce qui permet de
// relire le diff d'une montée de version au lieu de la subir.

import { createRequire } from 'node:module';
import { writeFileSync } from 'node:fs';

// Résolution explicite vers les dépendances du backend : ce script est le seul
// pont entre les deux, et une résolution implicite ferait chercher le paquet
// dans `apps/mobile/node_modules`, qui n'existe pas.
const requireBackend = createRequire(
  new URL('../../backend/package.json', import.meta.url),
);
const phone = requireBackend('libphonenumber-js');
const exemples = requireBackend('libphonenumber-js/examples.mobile.json');

const nomFr = new Intl.DisplayNames(['fr'], { type: 'region' });
const nomEn = new Intl.DisplayNames(['en'], { type: 'region' });
const nomAr = new Intl.DisplayNames(['ar'], { type: 'region' });

/** Échappe une chaîne pour une chaîne Dart entre guillemets doubles. */
function dart(chaine) {
  return `"${chaine.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\$/g, '\\$')}"`;
}

const lignes = phone
  .getCountries()
  .sort()
  .map((iso) => {
    const exemple = phone.getExampleNumber(iso, exemples);
    return (
      `  Pays(\n` +
      `    iso: ${dart(iso)},\n` +
      `    indicatif: ${dart(phone.getCountryCallingCode(iso))},\n` +
      `    nomFr: ${dart(nomFr.of(iso))},\n` +
      `    nomEn: ${dart(nomEn.of(iso))},\n` +
      `    nomAr: ${dart(nomAr.of(iso))},\n` +
      `    exemple: ${dart(exemple ? exemple.formatNational() : '')},\n` +
      `  ),`
    );
  });

const entete = `// GÉNÉRÉ PAR \`tool/generer_pays.mjs\` — NE PAS ÉDITER À LA MAIN.
//
// Régénérer :  cd apps/mobile && node tool/generer_pays.mjs
//              dart format lib/features/shared/data/pays.dart
//
// Source des indicatifs et des numéros d'exemple : libphonenumber-js
// (dépendance du backend, la MÊME bibliothèque que celle qui valide et
// normalise côté serveur — voir \`apps/backend/src/commercant/telephone.ts\`).
// Un serveur et une app qui ne partagent pas la même table des indicatifs
// s'accordent sur la saisie et divergent sur le refus.
//
// Source des noms : \`Intl.DisplayNames\` de Node (données CLDR).
`;

const corps = `${entete}
/// Un pays du sélecteur d'indicatif.
///
/// ⚠️ Le nom est porté en trois langues plutôt que localisé à l'exécution : ce
/// sont des données de référence, pas des chaînes d'interface, et elles n'ont
/// donc rien à faire dans les \`.arb\` (voir l'en-tête du générateur).
class Pays {
  const Pays({
    required this.iso,
    required this.indicatif,
    required this.nomFr,
    required this.nomEn,
    required this.nomAr,
    required this.exemple,
  });

  /// Code ISO 3166-1 alpha-2 — c'est LUI qui part au serveur, jamais le nom
  /// ni l'indicatif : le serveur en déduit le reste avec la même bibliothèque.
  final String iso;

  /// Indicatif téléphonique sans le \`+\` (\`213\` pour l'Algérie).
  final String indicatif;

  final String nomFr;
  final String nomEn;
  final String nomAr;

  /// Numéro national d'exemple, servi en \`hintText\` du champ téléphone.
  /// Vide si la bibliothèque n'en connaît pas pour ce pays.
  final String exemple;

  /// Drapeau en emoji, **calculé** depuis les deux lettres ISO plutôt que
  /// stocké : les indicateurs régionaux Unicode sont exactement les lettres
  /// A–Z décalées de 0x1F1A5.
  String get drapeau => String.fromCharCodes(
    iso.codeUnits.map((lettre) => lettre + 0x1F1A5),
  );

  /// Le nom dans la langue de l'interface, l'anglais servant de repli pour
  /// une langue que l'app ne connaît pas encore.
  String nomPour(String codeLangue) => switch (codeLangue) {
    'fr' => nomFr,
    'ar' => nomAr,
    _ => nomEn,
  };
}

/// Les 245 pays connus de libphonenumber, triés par code ISO.
///
/// Le tri d'affichage se fait sur le nom **localisé**, donc à l'exécution :
/// trier ici sur le français placerait « Émirats » ailleurs qu'en arabe.
const List<Pays> kTousLesPays = [
${lignes.join('\n')}
];

/// Le pays d'un code ISO, ou \`null\` s'il est inconnu.
///
/// ⚠️ \`null\` et non un repli sur l'Algérie : un code inconnu venu du serveur
/// est une donnée à voir, pas à masquer derrière une valeur plausible.
Pays? paysParIso(String iso) {
  for (final pays in kTousLesPays) {
    if (pays.iso == iso) return pays;
  }
  return null;
}
`;

writeFileSync(
  new URL('../lib/features/shared/data/pays.dart', import.meta.url),
  corps,
  'utf8',
);
console.log(`pays.dart généré — ${lignes.length} pays.`);
