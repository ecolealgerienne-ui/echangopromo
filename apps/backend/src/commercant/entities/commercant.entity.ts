import { Exclude } from 'class-transformer';
import {
  Column,
  CreateDateColumn,
  Entity,
  JoinColumn,
  ManyToOne,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';
import { Categorie } from '../../common/enums/categorie.enum';
import { Commune } from '../../commune/entities/commune.entity';
import { Zone } from '../../zone/entities/zone.entity';
import { Agent } from '../../agent/entities/agent.entity';

/** Cycle de vie du compte (specs §3.2). */
export enum CommercantAccountState {
  CREE_AGENT = 'cree_agent',
  EN_ATTENTE_REVENDICATION = 'en_attente_revendication',
  REVENDIQUE = 'revendique',
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

  @Column()
  adresse: string;

  @Column({ type: 'enum', enum: Categorie })
  categorie: Categorie;

  @ManyToOne(() => Commune)
  @JoinColumn({ name: 'communeId' })
  commune: Commune;

  @Column()
  communeId: string;

  /** Zone opérationnelle de l'agent qui a onboardé ce commerçant, si applicable. */
  @ManyToOne(() => Zone, { nullable: true, onDelete: 'SET NULL' })
  @JoinColumn({ name: 'zoneId' })
  zone: Zone | null;

  @Column({ type: 'varchar', nullable: true })
  zoneId: string | null;

  @ManyToOne(() => Agent, { nullable: true, onDelete: 'SET NULL' })
  @JoinColumn({ name: 'createdByAgentId' })
  createdByAgent: Agent | null;

  @Column({ type: 'varchar', nullable: true })
  createdByAgentId: string | null;

  @Column({
    type: 'enum',
    enum: CommercantAccountState,
    default: CommercantAccountState.EN_ATTENTE_REVENDICATION,
  })
  accountState: CommercantAccountState;

  @Column({ type: 'enum', enum: CommercantOriginVerification })
  originVerification: CommercantOriginVerification;

  @Exclude()
  @Column({ type: 'varchar', nullable: true })
  pinHash: string | null;

  @Column({ type: 'timestamptz', nullable: true })
  telephoneVerifiedAt: Date | null;

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
