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
@Index(['recipientType', 'recipientId', 'readAt'])
export class Notification {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'enum', enum: NotificationType })
  type: NotificationType;

  @Column({ type: 'enum', enum: NotificationRecipientType })
  recipientType: NotificationRecipientType;

  @Index()
  @Column()
  recipientId: string; // commercantId, agentId, or adminId selon recipientType

  @Column({ nullable: true })
  @Index()
  promoId?: string; // NULL si la notification n'est pas liée à une promo

  @Column()
  message: string; // Message localisé côté backend (ex. "Votre promo a été signalée")

  @Column({ type: 'jsonb', nullable: true })
  @Exclude()
  metadata?: Record<string, unknown>; // Context additionnel (ex. { promoDescription, reportCount })

  @Column({ type: 'timestamptz', nullable: true })
  readAt: Date | null;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
