import { Exclude } from 'class-transformer';
import {
  Column,
  CreateDateColumn,
  Entity,
  JoinTable,
  ManyToMany,
  PrimaryGeneratedColumn,
} from 'typeorm';
import { Commune } from '../../commune/entities/commune.entity';

/**
 * Compte agent terrain — créé exclusivement par l'Admin, pas d'auto-inscription
 * (specs §3.3). Rattaché à zéro, une ou plusieurs communes (many-to-many) :
 * un agent doit pouvoir couvrir plusieurs communes, voire une wilaya entière
 * (le concept de Zone opérationnelle séparée a été abandonné — un agent par
 * commune n'est pas soutenable, et le rôle agent lui-même est amené à
 * disparaître à l'extension multi-wilaya). "Assigner toute la wilaya" est une
 * simple commodité d'UI côté admin qui sélectionne en masse toutes les
 * communes de cette wilaya dans cette même relation — pas un champ distinct,
 * pour ne pas créer une deuxième source de vérité.
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

  @ManyToMany(() => Commune)
  @JoinTable({
    name: 'agent_communes',
    joinColumn: { name: 'agentId', referencedColumnName: 'id' },
    inverseJoinColumn: { name: 'communeId', referencedColumnName: 'id' },
  })
  communes: Commune[];

  /** Incrémenté pour révoquer tous les JWT émis avant (audit règle #6). */
  @Column({ type: 'int', default: 0 })
  tokenVersion: number;

  @CreateDateColumn()
  createdAt: Date;
}
