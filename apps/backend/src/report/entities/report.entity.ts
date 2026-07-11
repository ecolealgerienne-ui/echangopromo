import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryGeneratedColumn,
} from 'typeorm';

/**
 * Motif du signalement (plan de correction, Phase 5) — jusqu'ici l'admin ne
 * voyait qu'un nombre de signalements sans savoir pourquoi (périmé ?
 * arnaque ? photo trompeuse ?), rendant la décision de modération à
 * l'aveugle.
 */
export enum ReportReason {
  PERIME = 'perime',
  ARNAQUE = 'arnaque',
  PHOTO_TROMPEUSE = 'photo_trompeuse',
  AUTRE = 'autre',
}

/** Signalement "promo expirée / incorrecte" — max 1 par device par promo (§5.4). */
@Entity()
@Index(['promoId', 'deviceId'], { unique: true })
export class Report {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  /**
   * `uuid` explicite (pas le `varchar` par défaut de TypeORM pour un
   * `string`) : nécessaire pour la jointure SQL directe avec `promo.id`
   * dans `ReportService.pendingModerationQueryBuilder` — Postgres n'a pas
   * d'opérateur `=` implicite entre `uuid` et `character varying` sur une
   * comparaison colonne-colonne (contrairement à colonne-paramètre, où le
   * driver déduit le type depuis la colonne), trouvé au premier vrai test
   * de la file de modération admin.
   */
  @Column({ type: 'uuid' })
  promoId: string;

  @Column()
  deviceId: string;

  /** Nullable pour rester compatible avec les signalements déjà en base avant cette colonne. */
  @Column({ type: 'enum', enum: ReportReason, nullable: true })
  reason: ReportReason | null;

  @CreateDateColumn()
  createdAt: Date;
}
