import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryGeneratedColumn,
} from 'typeorm';

/**
 * Une ligne par (promo, device) : sert à compter les vues par device unique
 * plutôt qu'un compteur brut facilement gonflé par rafraîchissement (§3.2).
 */
@Entity()
@Index(['promoId', 'deviceId'], { unique: true })
export class PromoView {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  promoId: string;

  @Column()
  deviceId: string;

  @CreateDateColumn()
  createdAt: Date;
}
