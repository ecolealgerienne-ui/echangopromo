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
 * Une valeur illisible (`'abc'`, `''`, `Infinity`, un négatif) retombe sur
 * [defaut]. C'est un repli assumé, contre la règle #29, et pour une raison
 * précise : il n'existe pas de plafond « absent » qui aurait du sens ici, et
 * refuser au démarrage rendrait une faute de frappe dans `.env` capable
 * d'empêcher le backend de servir. Le repli est donc **journalisé** — c'est
 * ce qui le distingue d'un défaut silencieux : l'information d'absence n'est
 * pas détruite, elle est déplacée dans le journal.
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
     */
    minimum?: number;
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

  const plancher = options?.minimum ?? Number.MIN_VALUE;

  if (!Number.isFinite(n) || n <= 0) {
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

  if (n < plancher) {
    signaler(
      cle,
      `${cle ?? 'valeur'} de configuration sous le minimum autorisé (${n} < ${plancher}) — repli sur ${defaut}`,
    );
    return defaut;
  }

  return n;
}
