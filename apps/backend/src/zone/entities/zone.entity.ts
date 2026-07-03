import { Column, Entity, PrimaryGeneratedColumn } from 'typeorm';

/**
 * Découpage opérationnel interne pour les tournées d'agent, sans lien
 * direct avec le découpage administratif Commune (specs §5.2).
 */
@Entity()
export class Zone {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  nom: string;

  @Column({ type: 'text', nullable: true })
  description: string | null;
}
