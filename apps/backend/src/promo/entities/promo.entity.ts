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
 * Statuts (specs §4). `active` et `verifiee_ok` sont les deux statuts
 * visibles côté client — `verifiee_ok` reste affichée après qu'un
 * signalement a été jugé infondé par l'admin (§5.4).
 */
export enum PromoStatus {
  ACTIVE = 'active',
  EXPIREE = 'expiree',
  SIGNALEE = 'signalee',
  MASQUEE = 'masquee',
  VERIFIEE_OK = 'verifiee_ok',
}

/**
 * Seule source de vérité pour "qu'est-ce qu'une promo visible" — importée
 * partout où cette règle est nécessaire (client, statut de zone agent,
 * dashboard admin) pour éviter qu'elle ne diverge d'un service à l'autre.
 */
export const VISIBLE_PROMO_STATUSES = [
  PromoStatus.ACTIVE,
  PromoStatus.VERIFIEE_OK,
];

@Entity()
@Index(['status', 'dateFin'])
export class Promo {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @ManyToOne(() => Commercant, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'commercantId' })
  commercant: Commercant;

  @Index()
  @Column()
  commercantId: string;

  @Column()
  produit: string;

  @Column({ type: 'numeric', precision: 10, scale: 2 })
  prixAvant: string;

  @Column({ type: 'numeric', precision: 10, scale: 2 })
  prixApres: string;

  @Column({ type: 'enum', enum: Categorie })
  categorie: Categorie;

  /**
   * Clé de l'objet S3 (voir docs/ARCHITECTURE.md — structure de bucket).
   * Jamais exposée au client : pour les promos créées par un agent, cette
   * clé contient l'UUID de l'agent (pas du commerçant) — fuite d'identifiant
   * interne évitable. Le contrôleur expose `photoUrl` à la place.
   */
  @Exclude()
  @Column()
  photoKey: string;

  @Column({ type: 'timestamptz' })
  dateFin: Date;

  @Column({ type: 'enum', enum: PromoStatus, default: PromoStatus.ACTIVE })
  status: PromoStatus;

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
   * fichier image est purgé, indépendamment du statut fonctionnel.
   */
  @Column({ type: 'timestamptz', nullable: true })
  photoPurgedAt: Date | null;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
