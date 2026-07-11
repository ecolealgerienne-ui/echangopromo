import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { InjectRepository } from '@nestjs/typeorm';
import { LessThan, Repository, IsNull } from 'typeorm';
import { PaginatedResult, toPaginatedResult } from '../common/pagination/paginated-result';
import {
  Notification,
  NotificationRecipientType,
  NotificationType,
} from './entities/notification.entity';

/**
 * Fenêtre de rétention (purge quotidienne) : une notification lue n'a plus
 * d'utilité opérationnelle passé ce délai, une non lue reste plus longtemps
 * pour ne pas faire disparaître une alerte jamais traitée par le
 * destinataire (ex. commerçant qui n'ouvre pas l'app pendant plusieurs
 * semaines) — voir plan de correction post-audit admin/commerçant.
 */
const READ_RETENTION_DAYS = 30;
const UNREAD_RETENTION_DAYS = 90;

@Injectable()
export class NotificationService {
  private readonly logger = new Logger(NotificationService.name);

  constructor(
    @InjectRepository(Notification)
    private readonly notifications: Repository<Notification>,
  ) {}

  /**
   * Crée une notification pour un destinataire (commercant, agent ou admin).
   * Appelée par les services métier (modération, etc.) quand un événement digne de notification se produit.
   */
  async create(
    type: NotificationType,
    recipientType: NotificationRecipientType,
    recipientId: string,
    message: string,
    promoId?: string,
    metadata?: Record<string, unknown>,
  ): Promise<Notification> {
    return this.notifications.save(
      this.notifications.create({
        type,
        recipientType,
        recipientId,
        message,
        promoId,
        metadata,
      }),
    );
  }

  /**
   * Liste les notifications non lues d'un utilisateur (commercant, agent ou admin), paginées.
   */
  async listUnread(
    recipientType: NotificationRecipientType,
    recipientId: string,
    page: number,
    limit: number,
  ): Promise<PaginatedResult<Notification>> {
    const [items, total] = await this.notifications.findAndCount({
      where: {
        recipientType,
        recipientId,
        readAt: IsNull(),
      },
      order: { createdAt: 'DESC' },
      skip: (page - 1) * limit,
      take: limit,
    });
    return toPaginatedResult(items, total, page, limit);
  }

  /**
   * Liste toutes les notifications d'un utilisateur (lues + non lues),
   * paginées — historique complet, contrairement à `listUnread`.
   */
  async listAll(
    recipientType: NotificationRecipientType,
    recipientId: string,
    page: number,
    limit: number,
  ): Promise<PaginatedResult<Notification>> {
    const [items, total] = await this.notifications.findAndCount({
      where: { recipientType, recipientId },
      order: { createdAt: 'DESC' },
      skip: (page - 1) * limit,
      take: limit,
    });
    return toPaginatedResult(items, total, page, limit);
  }

  /**
   * Marque une notification comme lue — scopée au destinataire courant
   * (recipientType + recipientId dans le WHERE) pour qu'un utilisateur ne
   * puisse jamais marquer comme lue la notification d'un tiers en devinant
   * son id (règle #1 : le rôle JWT seul ne suffit jamais sur une ressource
   * qui pourrait appartenir à quelqu'un d'autre).
   */
  async markAsRead(
    notificationId: string,
    recipientType: NotificationRecipientType,
    recipientId: string,
  ): Promise<void> {
    await this.notifications.update(
      { id: notificationId, recipientType, recipientId },
      { readAt: new Date() },
    );
  }

  /**
   * Marque toutes les notifications non lues d'un utilisateur comme lues.
   */
  async markAllAsRead(
    recipientType: NotificationRecipientType,
    recipientId: string,
  ): Promise<void> {
    await this.notifications.update(
      {
        recipientType,
        recipientId,
        readAt: IsNull(),
      },
      { readAt: new Date() },
    );
  }

  /**
   * Compte les notifications non lues d'un utilisateur (pour un badge de compteur).
   */
  async countUnread(
    recipientType: NotificationRecipientType,
    recipientId: string,
  ): Promise<number> {
    return this.notifications.count({
      where: {
        recipientType,
        recipientId,
        readAt: IsNull(),
      },
    });
  }

  /** Purge quotidienne (voir constantes de rétention en tête de fichier). */
  @Cron(CronExpression.EVERY_DAY_AT_3AM)
  async purgeOldNotificationsCron(): Promise<void> {
    const count = await this.purgeOld();
    this.logger.log(`${count} notification(s) purgée(s)`);
  }

  async purgeOld(): Promise<number> {
    const readCutoff = new Date(Date.now() - READ_RETENTION_DAYS * 24 * 60 * 60 * 1000);
    const unreadCutoff = new Date(Date.now() - UNREAD_RETENTION_DAYS * 24 * 60 * 60 * 1000);

    // `readAt < cutoff` exclut déjà les non lues (NULL < date = NULL en SQL,
    // pas besoin de Not(IsNull()) explicite).
    const readResult = await this.notifications.delete({ readAt: LessThan(readCutoff) });
    const unreadResult = await this.notifications.delete({
      readAt: IsNull(),
      createdAt: LessThan(unreadCutoff),
    });

    return (readResult.affected ?? 0) + (unreadResult.affected ?? 0);
  }
}
