import { Exclude } from 'class-transformer';
import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  JoinColumn,
  ManyToOne,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';
import { Promo } from '../../promo/entities/promo.entity';

/**
 * Une diapositive du bandeau « Top promos » de l'accueil client, choisie par
 * l'admin.
 *
 * Jusqu'ici ce bandeau était purement calculé (`sort=discount` : la plus
 * forte réduction mathématique) — un commerçant saisissant un prix avant
 * gonflé trustait la vitrine, et l'admin n'avait aucun moyen d'y mettre en
 * avant une offre précise, une opération saisonnière ou une image dédiée.
 *
 * Deux dimensions **indépendantes**, volontairement :
 * - la **cible** (ce qui s'ouvre au clic) : la promo, ou rien du tout pour
 *   un bandeau purement informatif (annonce d'opération, visuel de saison) ;
 * - le **visuel** : `imageKey` si l'admin a importé une image, sinon la
 *   photo de la promo ciblée. Une image importée sur une diapositive qui
 *   cible une promo remplace donc la photo du commerçant sans y toucher —
 *   la fiche promo, elle, garde ses photos d'origine.
 *
 * Sans curation active, l'API retombe sur le classement calculé d'avant —
 * le bandeau ne disparaît jamais faute de configuration.
 */
@Entity()
// Nommé comme en base (`1783820000000-CreateHighlight`) — sans ça TypeORM
// calcule un nom de hachage, ne reconnaît plus l'index et propose de le
// remplacer par le sien à chaque `migration:generate` (2026-08-05).
@Index('IDX_highlight_active_position', ['active', 'position'])
export class Highlight {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  /**
   * Ordre d'affichage, croissant. Réaffecté en bloc par
   * `HighlightService.reorder` — jamais deviné à partir de `createdAt`, un
   * bandeau éditorial n'a aucune raison de suivre l'ordre de création.
   */
  @Column({ type: 'int', default: 0 })
  position: number;

  /** Permet de préparer une opération à l'avance sans la publier. */
  @Column({ type: 'boolean', default: true })
  active: boolean;

  /**
   * `SET NULL` plutôt que `CASCADE` : une promo purgée ne doit pas faire
   * disparaître silencieusement une diapositive que l'admin a composée
   * (titre, image importée) — elle redevient un bandeau sans cible, visible
   * dans la liste admin, qui reste corrigeable.
   */
  @ManyToOne(() => Promo, { onDelete: 'SET NULL', nullable: true })
  @JoinColumn({ name: 'promoId' })
  promo: Promo | null;

  // PostgreSQL n'indexe pas automatiquement une clé étrangère (CLAUDE.md
  // #12) — celle-ci sert de jointure à chaque chargement du bandeau. Nommé
  // comme en base, même raison que l'index composite ci-dessus.
  @Index('IDX_highlight_promo')
  @Column({ type: 'uuid', nullable: true })
  promoId: string | null;

  /**
   * Clé S3 de l'image importée par l'admin (`highlight-images/`), jamais
   * exposée telle quelle : elle contient l'UUID de l'admin, un identifiant
   * interne (même raisonnement que `Promo.photoKeys`, CLAUDE.md #4). Le
   * contrôleur expose `imageUrl`.
   */
  @Exclude()
  @Column({ type: 'varchar', nullable: true })
  imageKey: string | null;

  /** Surtitre optionnel — remplace la description de la promo à l'affichage. */
  @Column({ type: 'varchar', length: 60, nullable: true })
  titre: string | null;

  @Column({ type: 'varchar', length: 100, nullable: true })
  sousTitre: string | null;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
