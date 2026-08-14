/**
 * Lit un **nombre** de configuration, là où `ConfigService` ne rend que du
 * texte.
 *
 * ── Pourquoi cette fonction existe ────────────────────────────────────────
 *
 * `configService.get<number>('CLE', 5)` **ne convertit rien** : le `<number>`
 * est une assertion TypeScript, effacée à la compilation. `ConfigModule` est
 * monté sans `load` de conversion et `validateEnv` rend l'environnement
 * inchangé — donc dès que la variable est définie dans `.env` (et
 * `.env.example` en définit quatre), le service reçoit la **chaîne** `'5'`,
 * pas `5`.
 *
 * Ça passait inaperçu parce que tous les usages étaient arithmétiques et que
 * JavaScript coerce (`'5' * 86400000` marche, `count >= '5'` aussi). Le
 * masque tombe dès qu'une de ces valeurs **sort en JSON** : `GET
 * /promo/me/slots` aurait servi `{"plafond": "5"}`, et le mobile fait
 * `json['plafond'] as int` — un plantage de désérialisation, pas un mauvais
 * chiffre (revue 2026-08-05, règle #34 : établir que c'est un nombre fini,
 * jamais le supposer d'une annotation en amont).
 *
 * ── Ce qu'elle refuse, et ce qu'elle en fait ──────────────────────────────
 *
 * Une valeur illisible (`'abc'`, `''`, `Infinity`) ou hors de l'intervalle
 * attendu retombe sur [defaut]. C'est un repli assumé, contre la règle #29,
 * et pour une raison précise : il n'existe pas de plafond « absent » qui
 * aurait du sens ici, et refuser au démarrage rendrait une faute de frappe
 * dans `.env` capable d'empêcher le backend de servir. Le repli est donc
 * **journalisé** — c'est ce qui le distingue d'un défaut silencieux :
 * l'information d'absence n'est pas détruite, elle est déplacée dans le
 * journal.
 *
 * ── Pourquoi zéro et le négatif sont refusés PAR DÉFAUT, mais plus toujours ─
 *
 * Toutes les clés lues jusqu'ici sont des plafonds, des durées ou des
 * cooldowns : zéro et négatif n'y ont aucun sens, et le refus est éprouvé
 * (`config-number.spec.ts`). ⚠️ **Mais ce garde-fou n'était pas levable, et
 * `options.minimum` ne le levait pas** — il s'y ajoutait, le test `n <= 0`
 * étant appliqué avant le plancher.
 *
 * Ça n'avait aucune conséquence tant que la configuration ne portait que des
 * plafonds. Ça en a une le jour où elle porte une **coordonnée** : les
 * longitudes de tout l'ouest algérien sont négatives — Oran (−0.64), Tlemcen
 * (−1.31), Sidi Bel Abbès (−0.63). Régler la position par défaut sur Oran
 * aurait donné un backend qui démarre, sert Alger, et un journal que personne
 * ne relit (règle #36 : le repli qui fonctionne est ce qui rend l'absence
 * indiscernable de la présence).
 *
 * D'où la règle, **explicite et non déductible** : c'est un `minimum` **négatif
 * ou nul** qui déclare un intervalle signé et lève le garde-fou. Sans lui, le
 * refus de zéro et du négatif reste actif, exactement comme avant — un appelant
 * qui n'a rien demandé ne change pas de comportement.
 */
import { Logger } from '@nestjs/common';

const logger = new Logger('configNumber');

/**
 * Replis déjà signalés, pour ne le dire **qu'une fois par clé**.
 *
 * ⚠️ Ces fonctions sont appelées **par requête**, pas au démarrage
 * (`activeCap()` l'est depuis `assertUnderCap`). Sans cette mémoire, un `.env`
 * incomplet produirait une ligne de journal à chaque publication de promo —
 * et un avertissement répété mille fois est un avertissement qu'on filtre,
 * donc un repli redevenu silencieux par un autre chemin.
 */
const dejaSignale = new Set<string>();

function signaler(cle: string | undefined, message: string): void {
  const empreinte = `${cle ?? '?'}|${message}`;
  if (dejaSignale.has(empreinte)) return;
  dejaSignale.add(empreinte);
  logger.warn(message);
}

/** Réservé aux tests — la mémoire des replis signalés est un état de module. */
export function _resetConfigNumberLog(): void {
  dejaSignale.clear();
}

export function configNumber(
  brut: unknown,
  defaut: number,
  cle?: string,
  options?: {
    /**
     * Valeur minimale acceptée. En dessous, on retombe sur [defaut] **en le
     * journalisant** — comme pour une valeur illisible.
     *
     * ⚠️ **Un plancher n'est pas un détail de validation, c'est une règle
     * métier qui a déjà coûté.** Le seuil de modération avait été abaissé à 1
     * le 2026-07-12 pour une phase de test : un seul signalement suffisait
     * alors à masquer la promo d'un concurrent, `X-Device-Id` n'étant jamais
     * vérifié côté serveur. Rendre une valeur réglable sans borne, c'est
     * rendre ce genre de réglage possible **depuis un fichier**, sans revue.
     *
     * ⚠️ **Un minimum négatif ou nul fait plus que borner : il déclare un
     * intervalle signé** et lève le refus de zéro et du négatif (voir l'en-tête
     * du fichier). C'est volontairement le seul moyen de le lever — un appelant
     * qui passe `{ minimum: 2 }` garde le comportement d'avant, garde-fou
     * compris.
     */
    minimum?: number;

    /**
     * Valeur maximale acceptée. Au-dessus, repli journalisé.
     *
     * Née avec les coordonnées (`{ minimum: -180, maximum: 180 }`) : une
     * longitude à 4000 est aussi fausse qu'une longitude à `'abc'`, mais rien
     * ne la refusait — le refus de zéro et du négatif ne borde que d'un côté.
     * Règle #34, second temps : « un DTO décoré n'est pas un DTO borné », et
     * une lecture de configuration non plus.
     */
    maximum?: number;
  },
): number {
  // ⚠️ **L'absence se dit, elle aussi.** Elle ne se distingue autrement en
  // rien d'une clé présente valant exactement le défaut : le backend démarre,
  // sert la bonne valeur, et le jour où l'on change la variable sans effet on
  // conclura que le réglage est cassé plutôt qu'absent. C'est le cas réel de
  // `PROMO_ACTIVE_CAP`, ajouté aux `.env.example` mais pas au `.env` de WSL
  // qui, lui, tourne (règle #36).
  // `String(brut).trim()` serait tentant, mais `String([])` vaut `''` : un
  // tableau vide serait rapporté « absent » au lieu de « type inattendu ».
  if (
    brut === undefined ||
    brut === null ||
    (typeof brut === 'string' && brut.trim() === '')
  ) {
    signaler(
      cle,
      `${cle ?? 'valeur'} absente de la configuration — valeur retenue : ${defaut}`,
    );
    return defaut;
  }

  // ⚠️ N'accepter QUE `number` et `string`. `Number()` est bien trop
  // accueillant pour servir de garde : `Number(true)` vaut 1, `Number([5])`
  // vaut 5, `Number('')` et `Number(' ')` valent 0. Passer par lui sans
  // filtrer le type d'abord, c'est convertir des choses qui n'étaient pas des
  // nombres au lieu de les refuser.
  if (typeof brut !== 'number' && typeof brut !== 'string') {
    signaler(
      cle,
      `${cle ?? 'valeur'} de configuration d'un type inattendu (${typeof brut}) — repli sur ${defaut}`,
    );
    return defaut;
  }

  const n = Number(brut);

  if (!Number.isFinite(n)) {
    // ⚠️ `String`, pas `JSON.stringify` : ce dernier rend `null` pour `NaN`
    // **et** pour `Infinity`, effaçant du journal la seule chose qu'il doit
    // montrer. Ce message est la contrepartie du repli — s'il est illisible,
    // le repli redevient silencieux (règle #29).
    signaler(
      cle,
      `${cle ?? 'valeur'} de configuration illisible (${String(brut)}) — repli sur ${defaut}`,
    );
    return defaut;
  }

  // Un `minimum` négatif ou nul est la **déclaration** d'un intervalle signé.
  // Tout le reste — pas d'options, ou un minimum positif — garde le garde-fou
  // historique intact.
  const intervalleSigne =
    options?.minimum !== undefined && options.minimum <= 0;

  if (!intervalleSigne && n <= 0) {
    // Message distinct de « illisible » : `-3` se lit parfaitement, il est
    // refusé. Confondre les deux dans le journal, c'est faire chercher une
    // faute de frappe là où il y a un désaccord sur l'intervalle attendu.
    signaler(
      cle,
      `${cle ?? 'valeur'} de configuration nulle ou négative (${n}) — repli sur ${defaut}`,
    );
    return defaut;
  }

  if (options?.minimum !== undefined && n < options.minimum) {
    signaler(
      cle,
      `${cle ?? 'valeur'} de configuration sous le minimum autorisé (${n} < ${options.minimum}) — repli sur ${defaut}`,
    );
    return defaut;
  }

  if (options?.maximum !== undefined && n > options.maximum) {
    signaler(
      cle,
      `${cle ?? 'valeur'} de configuration au-dessus du maximum autorisé (${n} > ${options.maximum}) — repli sur ${defaut}`,
    );
    return defaut;
  }

  return n;
}
