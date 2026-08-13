import { Exclude } from 'class-transformer';
import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  JoinColumn,
  ManyToOne,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';
import { Categorie } from '../../common/enums/categorie.enum';
import { Agent } from '../../agent/entities/agent.entity';

/**
 * Cycle de vie du compte (specs §3.2). `CREE_AGENT` n'est plus jamais
 * assigné depuis le 2026-07-13 (l'agent choisit et transmet le PIN en
 * personne à la création, le compte est `autonome` dès le départ — voir
 * `CommercantService.createByAgent`) ; la valeur reste dans l'enum pour les
 * lignes déjà en base créées avant ce changement, dont le PIN se fixe
 * désormais via `CommercantService.resetPin` comme un PIN oublié ordinaire.
 */
export enum CommercantAccountState {
  CREE_AGENT = 'cree_agent',
  AUTONOME = 'autonome',
}

/**
 * Niveau de vérification d'origine (indépendant du cycle de vie, specs §3.2).
 * Le badge additionnel `vérifié_registre` est suivi séparément via
 * `registreStatus`, car il n'est jamais bloquant et peut s'ajouter aux deux
 * niveaux d'origine.
 */
export enum CommercantOriginVerification {
  AUTO_INSCRIT = 'auto_inscrit',
  CONFIRME_AGENT = 'confirme_agent',
}

export enum RegistreStatus {
  EN_ATTENTE = 'en_attente',
  VALIDE = 'valide',
  REJETE = 'rejete',
}

/**
 * Bornes de saisie du nom et de l'adresse — nommées ici, à côté des colonnes
 * qu'elles décrivent, et importées par les trois DTO d'entrée : la borne ne
 * doit exister qu'une fois (même convention que `PRIX_MAX`).
 *
 * ⚠️ **Ces deux champs n'avaient aucun plafond**, alors que la règle 34 nomme
 * précisément « un `@IsString` sans `@MaxLength` » comme une borne manquante,
 * pas un choix. Ils étaient déjà sans plafond avant le 2026-08-13 ; ce qui a
 * changé ce jour-là, c'est qu'`adresse` est devenue **le seul repère de lieu en
 * texte libre** du produit, après la suppression de `commune`/`wilaya`. Un
 * champ qu'on vient de promouvoir mérite une borne.
 *
 * ⚠️ **La colonne, elle, reste un `varchar` sans longueur — délibérément.**
 * Contrairement à `PRIX_MAX`, qui recopie une contrainte que Postgres applique
 * déjà (`numeric(10, 2)`), il n'y a ici *rien à refléter* : la base accepte
 * tout. Poser `@Column({ length: … })` exigerait une migration `ALTER TYPE` sur
 * une table de production pour une valeur que rien n'oblige, et ferait diverger
 * l'entité de la base tant qu'elle n'est pas écrite (règle 12). La borne est
 * donc une **décision produit sur l'entrée**, appliquée au seul endroit qui la
 * fait respecter — et c'est dit plutôt que sous-entendu.
 *
 * Les valeurs : 120 pour un nom de commerce, 200 pour une adresse écrite à la
 * main. **Mesuré avant de choisir** — sur les 129 fiches de la base de
 * développement au 2026-08-13, la plus longue adresse fait **25** caractères et
 * le plus long nom **22**. Les bornes sont donc à un ordre de grandeur des
 * saisies réelles : elles ne peuvent gêner personne aujourd'hui, et empêchent
 * qu'une fiche devienne un champ de texte libre déguisé.
 */
export const NOM_MAX_LENGTH = 120;
export const ADRESSE_MAX_LENGTH = 200;

/**
 * ⚠️ **`IDX_commercant_position` n'est PLUS déclaré ici, et son absence est
 * délibérée.**
 *
 * Depuis `CommercantPositionGistIndex1783880000000`, c'est un index **GiST sur
 * une expression** — `point("longitude", "latitude")` — et le décorateur
 * `@Index` de TypeORM ne sait décrire que des colonnes. Le déclarer avec
 * `['latitude', 'longitude']` ferait dire au modèle un btree que la base n'a
 * pas : `migration:generate` proposerait alors de remplacer le GiST par un
 * btree à chaque exécution, et la première migration appliquée sans relecture
 * défairait la décision du 2026-08-13.
 *
 * ⚠️ C'est le miroir de la règle 12, et il est ici assumé plutôt que tenu :
 * « un index en base sans `@Index()` est un candidat à la suppression ». Le
 * garde-fou n'est donc pas le décorateur mais **la mesure** — le critère du
 * dépôt reste qu'un `migration:generate` ne rende RIEN, et il a été vérifié
 * après ce changement. Le jour où il émet quelque chose sur cet index, c'est
 * ce commentaire qu'il faut venir relire.
 *
 * L'index lui-même est éprouvé par `test-plan-sql.sh`, qui vérifie qu'il est
 * emprunté quand on force le planificateur et qu'il ne remonte que les lignes
 * réellement dans le cadre.
 */
/**
 * ⚠️ **Unicité du numéro parmi les comptes actifs** — même raison que
 * ci-dessus, et le défaut s'était bel et bien produit : au 2026-08-05,
 * `migration:generate` émettait `DROP INDEX "UQ_commercant_telephone_active"`
 * **sans jamais le recréer dans le `up()`** (seul le `down()` le remettait).
 * Appliquer cette migration aurait silencieusement supprimé la garantie « un
 * seul commerçant actif par numéro » — celle qui vient d'être éprouvée par
 * `test-cycle-commercant.sh`, et dont l'absence avait produit P10.
 *
 * C'est le miroir de la règle 12 : un `@Index()` sans migration est un
 * commentaire, **et un index en base sans `@Index()` est un candidat à la
 * suppression**. Les deux sens doivent être tenus.
 *
 * Posé à l'origine par `1783770000000-CommercantTelephoneUniqueActiveOnly` ;
 * déclaré ici pour que le modèle et la base disent la même chose.
 */
@Index('UQ_commercant_telephone_active', ['telephone'], {
  unique: true,
  where: '"deletedAt" IS NULL',
})
@Entity()
export class Commercant {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  /**
   * Unique parmi les comptes actifs uniquement — index partiel
   * `WHERE "deletedAt" IS NULL`, pas une contrainte `unique` classique.
   *
   * ⚠️ Il est déclaré **sur la classe** (voir plus haut), pas ici : le
   * décorateur de propriété ne sait pas porter de clause `WHERE`. La version
   * précédente de ce commentaire disait « pas exprimable par ce décorateur
   * seul » et s'arrêtait là — ce qui se lisait comme « inexprimable », alors
   * que la forme de classe l'exprime très bien. L'index n'a donc jamais été
   * déclaré, et `migration:generate` proposait de le supprimer (2026-08-05).
   *
   * Sans ça, un
   * commerçant suspendu bloquait définitivement son numéro : impossible de
   * le donner ensuite au vrai propriétaire en cas de changement de main du
   * commerce (bug trouvé 2026-07-13, `assertPhoneAvailable` ne filtrait
   * pas non plus les lignes supprimées avant ce correctif).
   */
  @Column()
  telephone: string;

  @Column()
  nom: string;

  @Column({ type: 'varchar', nullable: true })
  adresse: string | null;

  @Column({ type: 'enum', enum: Categorie })
  categorie: Categorie;

  // ⚠️ **`communeId` a été détruite le 2026-08-13**, avec les tables `commune`
  // et `agent_communes` (migration `DropCommune`). Le lieu d'un commerce ne
  // s'exprime plus que par `latitude`/`longitude` — qui décident de tout — et
  // par `adresse`, texte libre facultatif et purement indicatif.
  //
  // Aucune recopie de la commune vers l'adresse : elle aurait écrit dans un
  // champ que les CGU font certifier « exact » au commerçant une valeur qu'il
  // n'a jamais fournie, et qu'il n'aurait pas pu effacer. Sauvegarde hors dépôt
  // prise avant le `DROP` — voir l'en-tête de la migration.

  /**
   * Plafond de promos actives **propre à ce commerçant**, ou `null` pour
   * suivre le réglage global (`PROMO_ACTIVE_CAP`).
   *
   * ⚠️ **`null` n'est pas « zéro », et c'est tout l'intérêt** : il dit « suit
   * le défaut », ce qu'aucune valeur numérique ne saurait exprimer. Écrire 5
   * en base pour dire « comme tout le monde » figerait ce commerçant le jour
   * où le global passerait à 8 — sans que personne ne s'en aperçoive
   * (règle #29 : un défaut n'a pas de valeur par défaut).
   *
   * Lu par `PromoService.plafondActif()`, qui est **l'unique endroit** où la
   * règle « propre au commerçant sinon global » est écrite : la garde à la
   * création et le décompte servi à l'écran passent tous deux par lui. Les
   * séparer ferait voir « 3 / 8 » à un commerçant refusé à sa quatrième promo.
   */
  @Column({ type: 'int', nullable: true })
  promoActiveCap: number | null;

  @ManyToOne(() => Agent, { nullable: true, onDelete: 'SET NULL' })
  @JoinColumn({ name: 'createdByAgentId' })
  createdByAgent: Agent | null;

  @Index()
  @Column({ type: 'varchar', nullable: true })
  createdByAgentId: string | null;

  @Column({
    type: 'enum',
    enum: CommercantAccountState,
    default: CommercantAccountState.CREE_AGENT,
  })
  accountState: CommercantAccountState;

  @Column({ type: 'enum', enum: CommercantOriginVerification })
  originVerification: CommercantOriginVerification;

  @Exclude()
  @Column({ type: 'varchar', nullable: true })
  pinHash: string | null;

  /**
   * Incrémenté pour révoquer tous les JWT émis avant (même mécanisme que
   * Agent/Admin, audit règle #6) — notamment lors d'un `resetPin`/`changePin` :
   * sans ça, changer le PIN n'empêche pas un JWT déjà émis de continuer à
   * fonctionner jusqu'à expiration (audit V1 §1).
   */
  @Column({ type: 'int', default: 0 })
  tokenVersion: number;

  /**
   * Clé S3 de la photo du commerce (optionnelle — pour que les clients
   * identifient facilement le commerce dans la liste/fiche). Jamais
   * exposée telle quelle : le contrôleur expose `photoUrl` à la place
   * (même précaution que `Promo.photoKey`).
   */
  @Exclude()
  @Column({ type: 'varchar', nullable: true })
  photoKey: string | null;

  /** Position GPS du commerce (optionnelle, capturée via le device — pas de Google Maps payant). */
  @Column({ type: 'double precision', nullable: true })
  latitude: number | null;

  @Column({ type: 'double precision', nullable: true })
  longitude: number | null;

  @Column({ type: 'enum', enum: RegistreStatus, nullable: true })
  registreStatus: RegistreStatus | null;

  /**
   * Clé S3 du justificatif de registre de commerce. Jamais exposée telle
   * quelle (même précaution que `pinHash`/`photoKey`) : un endpoint qui
   * renvoie l'entité brute ne doit jamais fuiter cette clé — accessible
   * uniquement via `StorageService.getPresignedUrl` (audit sécurité
   * 2026-07-11 : un agent pouvait reconstruire l'URL du document d'un
   * commerçant de sa commune, hors du contrôle "admin only" voulu par le
   * design — écran/rôle depuis étendus à l'agent le 2026-07-12, avec garde
   * IDOR équivalente, voir `AdminController.assertCanManageCommercant`).
   */
  @Exclude()
  @Column({ type: 'varchar', nullable: true })
  registreKey: string | null;

  @Column({ type: 'timestamptz', nullable: true })
  registreValidatedAt: Date | null;

  /**
   * Toute modification du profil (nom/adresse/catégorie/photo/position, via
   * `PATCH /commercant/me`) bloque la publication de promo jusqu'à ce
   * qu'un admin la valide (`POST /admin/commercant/:id/profile/valider`) —
   * décision produit du 2026-07-12, s'applique à **tous** les commerçants
   * (y compris `confirme_agent`, contrairement au blocage registre qui ne
   * concerne que `auto_inscrit`) : une fois le compte créé, toute
   * modification ultérieure repasse par un contrôle humain, quelle que
   * soit l'origine de vérification initiale. Purgé aussi par
   * `resolveRegistreVerification` (2026-07-12) : à l'inscription d'un
   * auto-inscrit, la photo boutique passe par `updateProfile` et allume ce
   * flag en même temps que le registre — la validation du registre couvre
   * donc aussi le profil pour ce cas précis, une seule action admin plutôt
   * que deux pour un nouveau compte.
   */
  @Column({ type: 'boolean', default: false })
  profilePendingReview: boolean;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;

  /**
   * Suppression de compte — soft delete uniquement, jamais de suppression
   * physique : conserve l'historique (promos, signalements). Déclenchée par
   * le commerçant lui-même (bouton "Supprimer mon compte") ou par
   * l'admin/agent (`CommercantService.deleteCommercant`). `null` = compte
   * non supprimé. Distinct de `suspendedAt` ci-dessous depuis le
   * 2026-07-14 (les deux partageaient ce même champ auparavant, ce qui
   * libérait par erreur le numéro de téléphone — voir `assertPhoneAvailable`
   * — dès qu'un admin suspendait un compte) : seule la suppression libère le
   * numéro et "supprime" les promos (`PromoLifecycleStatus.SUPPRIMEE`) ;
   * pas de restauration prévue (le numéro peut entre-temps avoir été
   * réattribué à un autre commerçant).
   */
  @Column({ type: 'timestamptz', nullable: true })
  deletedAt: Date | null;

  /**
   * Suspension — réversible et arbitraire (décision admin/agent sans motif
   * métier particulier requis), contrairement à `deletedAt`. Ne libère
   * jamais le numéro de téléphone. Dépublie les promos en cours (repassées
   * en `BROUILLON`, republication manuelle après levée de la suspension —
   * pas de republication automatique). Bloque la connexion comme
   * `deletedAt` (voir `CommercantService.login`).
   */
  @Column({ type: 'timestamptz', nullable: true })
  suspendedAt: Date | null;

  /**
   * Horodatage d'acceptation des CGU/politique de confidentialité (plan de
   * correction, Phase 4) — `null` uniquement pour les comptes créés par un
   * agent (confirmation en personne, pas de flux d'auto-inscription) ou
   * antérieurs à l'ajout de cette colonne.
   */
  @Column({ type: 'timestamptz', nullable: true })
  consentedAt: Date | null;
}
