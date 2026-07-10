import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, IsNull } from 'typeorm';
import { PaginatedResult, toPaginatedResult } from '../common/pagination/paginated-result';
import {
  Notification,
  NotificationRecipientType,
  NotificationType,
} from './entities/notification.entity';

@Injectable()
export class NotificationService {
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
   * Marque une notification comme lue.
   */
  async markAsRead(notificationId: string): Promise<void> {
    await this.notifications.update(
      { id: notificationId },
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
}
