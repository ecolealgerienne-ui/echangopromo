import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryGeneratedColumn,
} from 'typeorm';

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

  @CreateDateColumn()
  createdAt: Date;
}
