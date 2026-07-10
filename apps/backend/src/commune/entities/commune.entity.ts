import { Column, Entity, PrimaryGeneratedColumn } from 'typeorm';

/** Référentiel administratif officiel (wilaya -> commune). */
@Entity()
export class Commune {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  wilaya: string;

  @Column()
  nom: string;
}
