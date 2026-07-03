import { Exclude } from 'class-transformer';
import {
  Column,
  CreateDateColumn,
  Entity,
  JoinColumn,
  ManyToOne,
  PrimaryGeneratedColumn,
} from 'typeorm';
import { Zone } from '../../zone/entities/zone.entity';

/**
 * Compte agent terrain — créé exclusivement par l'Admin, pas d'auto-inscription
 * (specs §3.3). Rattaché à une Zone (nullable tant que l'admin ne l'a pas
 * encore assignée à une tournée).
 */
@Entity()
export class Agent {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ unique: true })
  email: string;

  @Exclude()
  @Column()
  passwordHash: string;

  @Column()
  nom: string;

  @ManyToOne(() => Zone, { nullable: true, onDelete: 'SET NULL' })
  @JoinColumn({ name: 'zoneId' })
  zone: Zone | null;

  @Column({ type: 'varchar', nullable: true })
  zoneId: string | null;

  @CreateDateColumn()
  createdAt: Date;
}
