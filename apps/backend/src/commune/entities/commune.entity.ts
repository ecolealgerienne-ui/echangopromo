import { Column, Entity, PrimaryGeneratedColumn } from 'typeorm';

/**
 * Référentiel administratif officiel (wilaya -> commune), distinct de la
 * Zone opérationnelle agent (specs §5.2 — ne pas fusionner les deux).
 */
@Entity()
export class Commune {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  wilaya: string;

  @Column()
  nom: string;
}
