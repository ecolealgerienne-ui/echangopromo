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
import { Commune } from '../../commune/entities/commune.entity';
import { Zone } from '../../zone/entities/zone.entity';
import { Agent } from '../../agent/entities/agent.entity';

/**
 * Cycle de vie du compte (specs §3.2). Sans OTP, il n'y a plus d'étape
 * intermédiaire de revendication : un commerçant créé par un agent reste
 * `cree_agent` jusqu'à ce qu'il définisse lui-même son PIN (`claim`), ce qui
 * le fait passer directement à `autonome`.
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

@Entity()
export class Commercant {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ unique: true })
  telephone: string;

  @Column()
  nom: string;

  @Column({ type: 'varchar', nullable: true })
  adresse: string | null;

  @Column({ type: 'enum', enum: Categorie })
  categorie: Categorie;

  @ManyToOne(() => Commune)
  @JoinColumn({ name: 'communeId' })
  commune: Commune;

  @Index()
  @Column()
  communeId: string;

  /** Zone opérationnelle de l'agent qui a onboardé ce commerçant, si applicable. */
  @ManyToOne(() => Zone, { nullable: true, onDelete: 'SET NULL' })
  @JoinColumn({ name: 'zoneId' })
  zone: Zone | null;

  @Index()
  @Column({ type: 'varchar', nullable: true })
  zoneId: string | null;

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
   * Agent/Admin, audit règle #6) — notamment lors d'un `adminResetPin` :
   * sans ça, effacer le PIN n'empêche pas un JWT déjà émis de continuer à
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

  @Column({ type: 'varchar', nullable: true })
  registreKey: string | null;

  @Column({ type: 'timestamptz', nullable: true })
  registreValidatedAt: Date | null;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
