import { Exclude } from 'class-transformer';
import {
  Column,
  CreateDateColumn,
  Entity,
  PrimaryGeneratedColumn,
} from 'typeorm';

/**
 * Compte agent terrain — créé exclusivement par l'Admin, pas
 * d'auto-inscription (specs §3.3).
 *
 * ⚠️ **L'agent n'a plus de territoire depuis le 2026-08-13.** Il était rattaché
 * à zéro, une ou plusieurs `Commune` par une relation many-to-many
 * (`agent_communes`), qui bornait tout ce qu'il pouvait voir et faire. Cette
 * relation est supprimée : un agent agit désormais sur **tout le parc**.
 *
 * Ce que ça retire, et qu'aucun autre mécanisme ne remplace :
 * - la garde d'appartenance de quatorze routes d'écriture (règle #1, levée par
 *   décision produit — voir `AdminController` et `PromoController`) ;
 * - la partition du travail de modération : tous les agents voient la même
 *   file, et les trois résolutions sont des `update` inconditionnels ;
 * - le seul moyen dont disposait l'admin pour **restreindre** un agent. Il n'y
 *   a plus de granularité entre « agent » et « admin moins deux écrans ».
 *
 * ⚠️ Le rôle lui-même est en sursis, et il l'était déjà : les specs comme
 * `CLAUDE.md` annonçaient sa disparition « à l'extension multi-wilaya ». Ce
 * chantier crée exactement l'état qu'ils décrivaient.
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

  /**
   * ⚠️ **Le seul frein qui reste.** Un agent global compromis dispose de
   * quatorze routes d'écriture sur tout le parc, sans plafond anti-abus. La
   * révocation par `tokenVersion` passe donc du statut de conformité à celui
   * de dernier recours — `revocation_jwt.py` avec elle (règle #6).
   */
  @Column({ type: 'int', default: 0 })
  @Column({ type: 'int', default: 0 })
  tokenVersion: number;

  @CreateDateColumn()
  createdAt: Date;
}
