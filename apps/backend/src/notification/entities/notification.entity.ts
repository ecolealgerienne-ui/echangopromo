import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';
import { Exclude } from 'class-transformer';

/**
 * ⚠️ **Pas de `@ManyToOne` vers le destinataire, et c'est voulu.** Une
 * notification vise indifféremment un commerçant, un agent ou un admin : le
 * couple (`recipientType`, `recipientId`) est **polymorphe**, ce qu'une clé
 * étrangère TypeORM ne sait pas exprimer sans trois colonnes nullables et
 * trois relations dont deux seraient toujours vides.
 *
 * Les imports `ManyToOne`, `JoinColumn`, `Commercant`, `Agent` et `Admin`
 * traînaient ici sans usage, restes d'une conception antérieure — retirés le
 * 2026-08-05, au premier `npm run lint` de la session. Ne pas les remettre :
 * l'index composite ci-dessous couvre l'accès, la contrainte référentielle
 * n'existe pas et ne peut pas exister.
 */

export enum NotificationType {
  PROMO_WARNED = 'promo_warned', // Admin a averti sur une promo signalée
  PROMO_HIDDEN = 'promo_hidden', // Admin a masqué une promo
  PROMO_VERIFIED = 'promo_verified', // Admin a validé une promo après signalements
  PROMO_EXPIRING_SOON = 'promo_expiring_soon', // Promo publiée expirant sous 24h (plan de correction, Phase 6)
  REGISTRE_VALIDATED = 'registre_validated', // Admin a validé le registre de commerce
  REGISTRE_REJECTED = 'registre_rejected', // Admin a rejeté le registre de commerce
  PROFILE_VALIDATED = 'profile_validated', // Admin a validé une modification de profil
}

export enum NotificationRecipientType {
  COMMERCANT = 'commercant',
  AGENT = 'agent',
  ADMIN = 'admin',
}

@Entity()
// ⚠️ **Nommé, et nommé EXACTEMENT comme en base** (2026-08-05). Sans nom
// explicite, TypeORM en calcule un par hachage, ne reconnaît plus l'index posé
// par `1783680000000-CreateNotificationEntity` et propose de le supprimer pour
// le recréer sous son propre nom. Inoffensif pris isolément — mais c'est ce
// bruit, répété sur cinq index, qui a masqué pendant des semaines un
// `DROP INDEX "UQ_commercant_telephone_active"` sans recréation dans le même
// diff. Une sortie de `migration:generate` qu'on parcourt en diagonale est une
// sortie qu'on ne lit pas.
@Index('IDX_notification_recipientType_recipientId_readAt', [
  'recipientType',
  'recipientId',
  'readAt',
])
export class Notification {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'enum', enum: NotificationType })
  type: NotificationType;

  @Column({ type: 'enum', enum: NotificationRecipientType })
  recipientType: NotificationRecipientType;

  /**
   * ⚠️ **Types explicites, et pas d'`@Index()` : l'entité doit décrire la
   * base telle qu'elle est.** `synchronize` est coupé — le schéma ne vient
   * que des migrations — donc un décorateur absent de
   * `1783680000000-CreateNotificationEntity` ne crée rien : c'est un
   * commentaire déguisé en index. Pire, il rendait le prochain
   * `migration:generate` **destructeur** : il aurait émis les `CREATE INDEX`
   * manquants *et*, `@CreateDateColumn()` valant `TIMESTAMP` sans fuseau
   * par défaut alors que la table est en `timestamptz`, un `ALTER COLUMN
   * "createdAt" TYPE TIMESTAMP` — perte du fuseau sur tout l'historique,
   * glissée dans une migration qu'on aurait crue purement additive (revue
   * 2026-08-05, règle #12).
   *
   * Les deux `@Index()` retirés plutôt que créés par migration : **aucune
   * requête ne les emprunterait.** Les six accès de `NotificationService`
   * filtrent tous sur `recipientType` + `recipientId` ensemble, couverts par
   * l'index composite ci-dessus, et rien ne lit jamais par `promoId` seul.
   * `report.entity.ts:38` est le jumeau déjà aligné.
   */
  @Column({ type: 'uuid' })
  recipientId: string; // commercantId, agentId, or adminId selon recipientType

  @Column({ type: 'uuid', nullable: true })
  promoId?: string; // NULL si la notification n'est pas liée à une promo

  @Column()
  message: string; // Message localisé côté backend (ex. "Votre promo a été signalée")

  @Column({ type: 'jsonb', nullable: true })
  @Exclude()
  metadata?: Record<string, unknown>; // Context additionnel (ex. { promoDescription, reportCount })

  @Column({ type: 'timestamptz', nullable: true })
  readAt: Date | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt: Date;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt: Date;
}
