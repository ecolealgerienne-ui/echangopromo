import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryGeneratedColumn,
} from 'typeorm';

/** Une ligne par (commerçant, device) — même principe que PromoView (§3.2). */
@Entity()
@Index(['commercantId', 'deviceId'], { unique: true })
export class CommercantView {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  commercantId: string;

  @Column()
  deviceId: string;

  @CreateDateColumn()
  createdAt: Date;
}
