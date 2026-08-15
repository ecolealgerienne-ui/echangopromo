import {
  AppException,
  BadRequestAppException,
  ForbiddenAppException,
} from '../common/errors/app-exception';
import { ErrorCode } from '../common/errors/error-code.enum';
import {
  CommercantOriginVerification,
  RegistreStatus,
} from './entities/commercant.entity';

/**
 * **La table ordonnée des motifs qui empêchent de publier une promo.**
 *
 * Elle existe parce que cette règle avait deux consommateurs qui ne peuvent pas
 * partager le même code : les **gardes**, qui prennent une fiche chargée et
 * *lèvent* ; et l'**export CRM** (`docs/SPEC_INTEGRATION_ECHANGOCRM.md` §5), qui
 * doit rendre un booléen et un motif pour des milliers de commerçants d'un
 * coup. La spécification a d'abord demandé « une fonction unique appelée par les
 * deux » — c'est irréalisable : un `throw` par ligne et une expression évaluée
 * en masse ne sont pas la même chose.
 *
 * Ce qui **peut** être unique, c'est la table elle-même : une **donnée**, pas du
 * code. Chaque rendu la parcourt dans l'ordre et n'y ajoute rien. Ajouter un
 * motif ici le fait apparaître dans les deux rendus à la fois ; l'ajouter
 * ailleurs est ce que `publication-eligibility.spec.ts` refuse.
 *
 * ⚠️ **L'ordre est signifiant, ce n'est pas une liste.** C'est celui de
 * l'exécution réelle de `PromoService.create`/`publish` : compte, puis registre,
 * puis profil, puis position, puis plafond, puis quota de créations. Un
 * commerçant suspendu **et** sans position doit s'entendre dire qu'il est
 * suspendu — l'autre message l'enverrait réparer une donnée sur un compte qui ne
 * publiera de toute façon pas.
 *
 * ⚠️ **Un motif n'est pas un `ErrorCode`.** Ils ont deux publics : le motif est
 * lu par l'équipe commerciale, qui doit distinguer « il n'a rien envoyé » de
 * « nous n'avons pas traité son dossier » — trois motifs de registre pour un
 * seul code d'erreur, parce que le commerçant, lui, n'a qu'une chose à savoir.
 * Multiplier les `ErrorCode` obligerait à trois entrées dans chacun des trois
 * mappings mobile (règle 26) pour une distinction dont l'app n'a que faire.
 */
export enum MotifBlocagePublication {
  COMPTE_SUPPRIME = 'compte_supprime',
  COMPTE_SUSPENDU = 'compte_suspendu',
  /** Auto-inscrit qui n'a **jamais** envoyé de registre — à lui d'agir. */
  REGISTRE_ABSENT = 'registre_absent',
  /** Registre envoyé, **notre** file ne l'a pas traité — à nous d'agir. */
  REGISTRE_EN_ATTENTE = 'registre_en_attente',
  REGISTRE_REJETE = 'registre_rejete',
  PROFIL_EN_REVUE = 'profil_en_revue',
  POSITION_ABSENTE = 'position_absente',
  PLAFOND_ATTEINT = 'plafond_atteint',
  QUOTA_CREATION_24H = 'quota_creation_24h',
}

/**
 * Ce qu'une règle exige pour être évaluée.
 *
 * ⚠️ **La distinction n'est pas cosmétique** : une règle `agregat` a besoin de
 * comptages que seule une transaction sous verrou (côté gardes) ou la requête
 * d'export (côté CRM) sait produire. Une évaluation qui ne dispose pas des
 * agrégats doit **le dire**, jamais rendre « rien ne bloque » — ce serait un
 * défaut avec une valeur par défaut (règle #29), et le CRM afficherait
 * « peut publier » sur un commerçant au plafond.
 */
export type PorteeRegle = 'fiche' | 'agregat';

/** Les faits lisibles sur la seule fiche commerçant. */
export interface FaitsFiche {
  deletedAt: Date | null;
  suspendedAt: Date | null;
  originVerification: CommercantOriginVerification;
  registreStatus: RegistreStatus | null;
  profilePendingReview: boolean;
  latitude: number | null;
  longitude: number | null;
}

/** Les faits qui demandent un comptage. */
export interface FaitsAgregat {
  /** Promos `PUBLIEE` dont la `dateFin` est encore dans le futur. */
  promosEnLigne: number;
  /** `promoActiveCap` du commerçant, sinon `PROMO_ACTIVE_CAP`. */
  plafondEffectif: number;
  /** Promos créées sur les 24 dernières heures glissantes, brouillons compris. */
  creations24h: number;
  quotaCreation24h: number;
  /**
   * Agent ou admin agissant pour le compte du commerçant : exempté du **seul**
   * quota anti-abus de créations. Le plafond de promos actives est une règle
   * métier structurelle, personne n'en est exempté.
   */
  acteurDeConfiance: boolean;
}

/**
 * Ce qu'une règle reçoit. Tout y est facultatif **au type**, parce qu'une garde
 * d'agrégat n'a pas la fiche sous la main et réciproquement.
 *
 * ⚠️ **La complétude est tenue par les points d'entrée, pas par le type.**
 * `regleFicheApplicable` et `evaluerPublication` exigent des faits complets ;
 * `regleParMotif` est la seule échappatoire, et ses deux appelants fournissent
 * exactement ce que leur règle lit. Une règle qui recevrait un fait absent
 * **bloque** plutôt que de laisser passer — c'est le sens de la règle #29 : un
 * fait manquant n'a pas de valeur par défaut, et la valeur la moins coûteuse
 * est le refus.
 */
export type FaitsPublication = Partial<FaitsFiche> & Partial<FaitsAgregat>;

/**
 * `forbidden` ou `bad_request` : la table porte aussi le **statut HTTP**, parce
 * que c'est un fait de la règle et non une décision du rendu. Deux rendus qui
 * choisiraient chacun leur statut recréeraient la divergence que cette table
 * ferme.
 */
export type StatutRefus = 'forbidden' | 'bad_request';

/**
 * **Les noms de colonnes que le rendu SQL attend.**
 *
 * La requête d'export (`CrmExportService`) doit produire exactement ces
 * alias — c'est le contrat entre la table et elle. Les nommer ici plutôt que
 * de les écrire à la volée dans chaque expression évite qu'un renommage n'en
 * corrige que la moitié.
 */
export const COLONNES_SQL = {
  deletedAt: 'f."deletedAt"',
  suspendedAt: 'f."suspendedAt"',
  origine: 'f."originVerification"',
  registre: 'f."registreStatus"',
  profilEnRevue: 'f."profilePendingReview"',
  latitude: 'f."latitude"',
  longitude: 'f."longitude"',
  promosEnLigne: 'a.promos_en_ligne',
  plafond: 'a.plafond_effectif',
  creations24h: 'a.creations_24h',
  quota: 'a.quota_creation_24h',
} as const;

export interface RegleBlocage {
  motif: MotifBlocagePublication;
  portee: PorteeRegle;
  statut: StatutRefus;
  code: ErrorCode;
  applique: (faits: FaitsPublication) => boolean;
  message: (faits: FaitsPublication) => string;
  /**
   * Le **second rendu** : la même condition, en SQL, sur les colonnes de
   * `COLONNES_SQL`.
   *
   * ⚠️ **Ce n'est pas une seconde écriture de la règle, c'est une seconde
   * lecture de la même ligne.** Ce qui l'empêche de diverger du prédicat
   * TypeScript n'est pas la proximité dans le fichier — c'est le contrôle
   * exécuté : l'export rend les FAITS en même temps que le motif, et le banc
   * recalcule le motif en TypeScript depuis ces faits pour exiger l'égalité.
   * Un commentaire ne peut pas échouer (règle #30) ; ce contrôle, si.
   *
   * ⚠️ **`acteurDeConfiance` n'existe pas en SQL** : l'export décrit ce qu'un
   * commerçant peut faire LUI-MÊME, jamais ce qu'un agent pourrait faire à sa
   * place. Le quota s'y évalue donc toujours, là où la garde l'exempte.
   */
  sql: string;
}

/**
 * ⚠️ **Toute modification de cet ordre change le message rendu à un commerçant
 * qui cumule deux blocages.** `publication-eligibility.spec.ts` le fige cas par
 * cas ; ce n'est pas une contrainte de style, c'est la seule chose qui empêche
 * un réordonnancement accidentel de passer inaperçu.
 */
export const REGLES_PUBLICATION: readonly RegleBlocage[] = [
  {
    // Compte supprimé ou suspendu (soft dans les deux cas). Le commerçant
    // lui-même est déjà arrêté en amont — suspension et suppression révoquent
    // son token (`tokenVersion`) — mais **pas l'agent ni l'admin**, qui
    // agissent avec le leur : `create`/`publish` acceptaient donc de republier
    // pour un commerçant suspendu, défaisant la cascade qui venait de repasser
    // ses promos en brouillon (revue 2026-08-05).
    //
    // ⚠️ Deux motifs pour **un seul** `ErrorCode` : la garde d'origine
    // n'exposait que `COMMERCANT_ACCOUNT_INACTIVE`, et le CRM a besoin de la
    // distinction (un compte supprimé est terminal, un compte suspendu se
    // réactive).
    motif: MotifBlocagePublication.COMPTE_SUPPRIME,
    sql: `${COLONNES_SQL.deletedAt} IS NOT NULL`,
    portee: 'fiche',
    statut: 'forbidden',
    code: ErrorCode.COMMERCANT_ACCOUNT_INACTIVE,
    applique: (f) => f.deletedAt !== null,
    message: () => 'Ce compte commerçant est suspendu ou supprimé',
  },
  {
    motif: MotifBlocagePublication.COMPTE_SUSPENDU,
    sql: `${COLONNES_SQL.suspendedAt} IS NOT NULL`,
    portee: 'fiche',
    statut: 'forbidden',
    code: ErrorCode.COMMERCANT_ACCOUNT_INACTIVE,
    applique: (f) => f.suspendedAt !== null,
    message: () => 'Ce compte commerçant est suspendu ou supprimé',
  },
  // Un commerçant auto-inscrit (`AUTO_INSCRIT`) ne peut publier qu'une fois son
  // registre validé par un admin — décision produit du 2026-07-11, qui remplace
  // le badge `vérifié_registre` non-bloquant des specs §3.2/§5.4. Un commerçant
  // créé par un agent (`CONFIRME_AGENT`) est vérifié en personne et n'est
  // **jamais** concerné.
  //
  // ⚠️ Les trois états ne demandent pas le même geste, et c'est toute la raison
  // de les séparer : `null` = il n'a rien envoyé (à lui d'agir) ; `en_attente` =
  // nous ne l'avons pas traité (à nous) ; `rejete` = il doit renvoyer. Fondus en
  // un seul motif, l'écran « À débloquer » du CRM devient inutilisable.
  {
    motif: MotifBlocagePublication.REGISTRE_ABSENT,
    sql: `${COLONNES_SQL.origine} = 'auto_inscrit' AND ${COLONNES_SQL.registre} IS NULL`,
    portee: 'fiche',
    statut: 'forbidden',
    code: ErrorCode.COMMERCANT_REGISTRE_NOT_VALIDATED,
    applique: (f) =>
      f.originVerification === CommercantOriginVerification.AUTO_INSCRIT &&
      f.registreStatus === null,
    message: () => MESSAGE_REGISTRE,
  },
  {
    motif: MotifBlocagePublication.REGISTRE_EN_ATTENTE,
    sql: `${COLONNES_SQL.origine} = 'auto_inscrit' AND ${COLONNES_SQL.registre} = 'en_attente'`,
    portee: 'fiche',
    statut: 'forbidden',
    code: ErrorCode.COMMERCANT_REGISTRE_NOT_VALIDATED,
    applique: (f) =>
      f.originVerification === CommercantOriginVerification.AUTO_INSCRIT &&
      f.registreStatus === RegistreStatus.EN_ATTENTE,
    message: () => MESSAGE_REGISTRE,
  },
  {
    motif: MotifBlocagePublication.REGISTRE_REJETE,
    sql: `${COLONNES_SQL.origine} = 'auto_inscrit' AND ${COLONNES_SQL.registre} = 'rejete'`,
    portee: 'fiche',
    statut: 'forbidden',
    code: ErrorCode.COMMERCANT_REGISTRE_NOT_VALIDATED,
    applique: (f) =>
      f.originVerification === CommercantOriginVerification.AUTO_INSCRIT &&
      f.registreStatus === RegistreStatus.REJETE,
    message: () => MESSAGE_REGISTRE,
  },
  {
    // Contrairement au registre, s'applique à **tous** les commerçants sans
    // exception d'origine — décision produit du 2026-07-12 : toute modification
    // de profil, même pour un compte confirmé par un agent, repasse par un
    // contrôle admin avant de pouvoir publier.
    motif: MotifBlocagePublication.PROFIL_EN_REVUE,
    sql: `${COLONNES_SQL.profilEnRevue} = true`,
    portee: 'fiche',
    statut: 'forbidden',
    code: ErrorCode.COMMERCANT_PROFILE_PENDING_REVIEW,
    applique: (f) => f.profilePendingReview === true,
    message: () =>
      'Les modifications de votre profil doivent être validées par un administrateur avant de pouvoir publier des promos',
  },
  {
    // Sans position, une promo n'est **visible par personne** : les clients
    // cherchent par proximité et la carte filtre sur un cadre, qu'un `NULL` ne
    // peut pas satisfaire. Publier serait un geste sans effet — et le
    // commerçant verrait « 3 en ligne » sur un stock que personne ne voit
    // (règle #8).
    //
    // ⚠️ **`=== null`, pas la véracité.** `!f.longitude` refuserait une
    // longitude à `0`, qui est le méridien de Greenwich — une coordonnée
    // parfaitement légitime. Même piège que `configNumber`.
    //
    // ⚠️ **Jamais évaluée sur un brouillon** : les gardes posées pour tout le
    // monde refusaient aussi « Enregistrer comme brouillon », avec un message
    // parlant de publier sur un geste qui ne publie pas (revue 2026-08-05).
    // Préparer ne demande pas de point ; mettre en ligne, si.
    motif: MotifBlocagePublication.POSITION_ABSENTE,
    sql: `${COLONNES_SQL.latitude} IS NULL OR ${COLONNES_SQL.longitude} IS NULL`,
    portee: 'fiche',
    statut: 'forbidden',
    code: ErrorCode.COMMERCANT_POSITION_REQUIRED,
    applique: (f) => f.latitude === null || f.longitude === null,
    message: () =>
      'Indiquez la position de votre commerce pour pouvoir publier : les clients cherchent les promos autour d’eux',
  },
  {
    // Plafond de promos actives (specs §5.3), compté sur `PUBLIEE` **et**
    // `dateFin > maintenant` : une promo expirée mais pas encore basculée par le
    // cron de 1 h n'occupe plus d'emplacement. Personne n'en est exempté.
    motif: MotifBlocagePublication.PLAFOND_ATTEINT,
    sql: `${COLONNES_SQL.promosEnLigne} > ${COLONNES_SQL.plafond}`,
    portee: 'agregat',
    statut: 'bad_request',
    code: ErrorCode.PROMO_ACTIVE_CAP_REACHED,
    applique: (f) => f.promosEnLigne! >= f.plafondEffectif!,
    message: (f) =>
      `Plafond de ${f.plafondEffectif} promos actives atteint pour ce commerçant`,
  },
  {
    // Anti-abus (retour terrain 2026-07-14) : sans ce plafond, un commerçant
    // pourrait créer une promo en boucle rien que pour profiter du tri « plus
    // récentes en premier ». Compte **toutes** les créations, brouillons
    // compris, sur une fenêtre glissante de 24 h — pas un jour calendaire, sans
    // quoi il suffirait d'attendre minuit.
    motif: MotifBlocagePublication.QUOTA_CREATION_24H,
    sql: `${COLONNES_SQL.creations24h} >= ${COLONNES_SQL.quota}`,
    portee: 'agregat',
    statut: 'bad_request',
    code: ErrorCode.PROMO_DAILY_CREATION_CAP_REACHED,
    applique: (f) =>
      !f.acteurDeConfiance && f.creations24h! >= f.quotaCreation24h!,
    message: (f) =>
      `Plafond de ${f.quotaCreation24h} créations de promo par 24h atteint pour ce commerçant`,
  },
];

/**
 * Rendu n° 3 — l'exception. Le statut HTTP et le code viennent de la table, pas
 * du site d'appel : c'est ce qui garantit qu'un refus rendu par une garde et le
 * motif rendu au CRM parlent du même fait.
 */
export function exceptionDeRefus(
  regle: RegleBlocage,
  faits: FaitsPublication,
): AppException {
  const message = regle.message(faits);
  return regle.statut === 'forbidden'
    ? new ForbiddenAppException(regle.code, message)
    : new BadRequestAppException(regle.code, message);
}

/**
 * Message unique des trois états de registre. Nommé une fois : trois copies
 * d'une même phrase divergeraient à la première reformulation, et le commerçant
 * n'a de toute façon qu'un seul geste à faire.
 */
const MESSAGE_REGISTRE =
  'Votre registre de commerce doit être validé par un administrateur avant de pouvoir publier des promos';

/**
 * La règle d'un motif précis.
 *
 * Réservé aux gardes de portée `agregat`, qui sont **évaluées à des moments
 * différents** : le plafond de promos actives ne concerne pas un brouillon, le
 * quota de créations si. Le site d'appel choisit donc *laquelle* il évalue —
 * mais ni sa condition, ni son code, ni son message, ni son statut, qui restent
 * dans la table. C'est la seule liberté laissée à un rendu.
 */
export function regleParMotif(motif: MotifBlocagePublication): RegleBlocage {
  const regle = REGLES_PUBLICATION.find((r) => r.motif === motif);
  if (!regle) {
    // Inatteignable tant que l'enum et la table sont alignés — ce que le banc
    // vérifie. L'écrire quand même : un `undefined` silencieux ferait passer
    // une règle disparue pour une règle satisfaite.
    throw new Error(`Motif de blocage inconnu dans la table : ${motif}`);
  }
  return regle;
}

/** Le premier motif applicable parmi une portée donnée, `null` si aucun. */
function premierMotif(
  faits: FaitsPublication,
  portees: readonly PorteeRegle[],
): RegleBlocage | null {
  return (
    REGLES_PUBLICATION.find(
      (regle) => portees.includes(regle.portee) && regle.applique(faits),
    ) ?? null
  );
}

/**
 * Rendu n° 1 — la fiche seule. Utilisé par les gardes de
 * `PromoService.create`/`publish`, qui n'ont pas encore les agrégats à ce stade
 * (ils sont comptés plus loin, sous verrou consultatif).
 */
export function regleFicheApplicable(faits: FaitsFiche): RegleBlocage | null {
  return premierMotif(faits, ['fiche']);
}

/**
 * Les deux seules règles évaluables **avant** de savoir si le geste publie.
 *
 * `create({ asDraft: true })` doit refuser un compte mort — enregistrer un
 * brouillon sur un compte supprimé n'a aucun sens — mais ne doit refuser **rien
 * d'autre** : un commerçant dont le profil est en relecture doit pouvoir
 * préparer ses promos en attendant.
 */
export function regleCompteApplicable(faits: FaitsFiche): RegleBlocage | null {
  const regle = premierMotif(faits, ['fiche']);
  return regle && MOTIFS_COMPTE.includes(regle.motif) ? regle : null;
}

const MOTIFS_COMPTE: readonly MotifBlocagePublication[] = [
  MotifBlocagePublication.COMPTE_SUPPRIME,
  MotifBlocagePublication.COMPTE_SUSPENDU,
];

/**
 * Rendu n° 2 — fiche **et** agrégats, l'évaluation complète.
 *
 * C'est ce que consomme l'export CRM. Il exige les agrégats : les rendre
 * facultatifs ferait répondre « peut publier » à un commerçant au plafond, et le
 * commercial l'appellerait pour lui demander ce que le serveur refuse.
 */
export function evaluerPublication(faits: FaitsFiche & FaitsAgregat): {
  peutPublier: boolean;
  motif: MotifBlocagePublication | null;
} {
  const regle = premierMotif(faits, ['fiche', 'agregat']);
  return { peutPublier: regle === null, motif: regle?.motif ?? null };
}
