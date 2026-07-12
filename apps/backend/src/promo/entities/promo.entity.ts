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
import { Commercant } from '../../commercant/entities/commercant.entity';

/**
 * Cycle de vie éditorial (specs §3.2, workflow brouillon/publication/arrêt) —
 * volontairement séparé de `PromoModerationStatus` (CLAUDE.md #8 : ne jamais
 * combiner cycle de vie et modération dans un seul enum, leçon tirée d'un
 * bug réel de comptage avant ce projet). Le commerçant peut éditer une promo
 * quel que soit son statut ici.
 */
export enum PromoLifecycleStatus {
  BROUILLON = 'brouillon',
  PUBLIEE = 'publiee',
  ARRETEE = 'arretee',
  EXPIREE = 'expiree',
}

/**
 * Statut de modération (specs §5.4), indépendant du cycle de vie ci-dessus.
 * `normale` et `verifiee_ok` sont les deux valeurs qui n'empêchent pas la
 * visibilité client — `verifiee_ok` reste affichée après qu'un signalement
 * a été jugé infondé par l'admin, avec fenêtre d'ignore de 30 jours.
 */
export enum PromoModerationStatus {
  NORMALE = 'normale',
  SIGNALEE = 'signalee',
  MASQUEE = 'masquee',
  VERIFIEE_OK = 'verifiee_ok',
}

/**
 * Seule source de vérité pour "qu'est-ce qu'une promo visible" (avec
 * `lifecycleStatus = PUBLIEE` et `dateFin > NOW()` en plus) — importée
 * partout où cette règle est nécessaire pour éviter qu'elle ne diverge d'un
 * service à l'autre.
 */
export const VISIBLE_MODERATION_STATUSES = [
  PromoModerationStatus.NORMALE,
  PromoModerationStatus.VERIFIEE_OK,
];

@Entity()
@Index(['lifecycleStatus', 'dateFin'])
export class Promo {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @ManyToOne(() => Commercant, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'commercantId' })
  commercant: Commercant;

  @Index()
  @Column()
  commercantId: string;

  @Column({ length: 140 })
  description: string;

  @Column({ type: 'numeric', precision: 10, scale: 2 })
  prixAvant: string;

  @Column({ type: 'numeric', precision: 10, scale: 2 })
  prixApres: string;

  @Column({ type: 'enum', enum: Categorie })
  categorie: Categorie;

  /**
   * Clés des objets S3, jusqu'à 3, ordonnées (voir docs/ARCHITECTURE.md —
   * structure de bucket ; décision produit 2026-07-12, une seule photo ne
   * suffit pas à juger un produit). Jamais exposées publiquement : pour les
   * promos créées par un agent, ces clés contiennent l'UUID de l'agent (pas
   * du commerçant) — fuite d'identifiant interne évitable. Le contrôleur
   * expose `photoUrls` à la place, et ne réexpose les clés brutes que sur
   * `GET /promo/me/all` (propriétaire authentifié uniquement) pour permettre
   * l'édition sans réuploader les photos inchangées.
   */
  @Exclude()
  @Column('text', { array: true })
  photoKeys: string[];

  /**
   * Miniature (~240px) générée côté serveur à partir de la 1ère photo
   * uniquement (décision produit 2026-07-12 — seule la photo principale
   * sert de vignette dans les listes, les photos 2/3 ne sont jamais
   * affichées en petit). `null` si la génération a échoué (best-effort,
   * ne bloque jamais la création/édition — voir
   * `PromoService.tryGenerateThumbnail`) : le contrôleur retombe alors sur
   * la photo complète.
   */
  @Exclude()
  @Column({ type: 'varchar', nullable: true })
  thumbnailKey: string | null;

  /** Null tant que la promo est en `brouillon` — fixée à la publication. */
  @Column({ type: 'timestamptz', nullable: true })
  dateFin: Date | null;

  @Column({
    type: 'enum',
    enum: PromoLifecycleStatus,
    default: PromoLifecycleStatus.BROUILLON,
  })
  lifecycleStatus: PromoLifecycleStatus;

  @Column({
    type: 'enum',
    enum: PromoModerationStatus,
    default: PromoModerationStatus.NORMALE,
  })
  moderationStatus: PromoModerationStatus;

  /**
   * Horodatage de la dernière validation admin en `verifiee_ok`. Sert de
   * fenêtre glissante de 30 jours pendant laquelle les signalements
   * antérieurs à cette date ne comptent plus dans le seuil de modération
   * (specs §5.4) — voir ReportService.countActiveReports.
   */
  @Column({ type: 'timestamptz', nullable: true })
  verifiedOkAt: Date | null;

  /**
   * Horodatage de suppression du fichier S3 (rétention 1 mois, specs §5.8).
   * Les métadonnées de la promo restent en base indéfiniment — seul le
   * fichier image est purgé, indépendamment du cycle de vie.
   */
  @Column({ type: 'timestamptz', nullable: true })
  photoPurgedAt: Date | null;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
