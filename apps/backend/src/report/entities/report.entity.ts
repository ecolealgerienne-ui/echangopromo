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

  @Column()
  promoId: string;

  @Column()
  deviceId: string;

  @CreateDateColumn()
  createdAt: Date;
}
